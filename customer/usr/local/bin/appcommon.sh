#!/bin/bash
# Ver: 1.0 by Endial Fang (endial@126.com)
# 
# 应用通用业务处理函数

# 加载依赖脚本
. /usr/local/scripts/libcommon.sh       # 通用函数库

. /usr/local/scripts/libfile.sh
. /usr/local/scripts/libfs.sh
. /usr/local/scripts/libos.sh
. /usr/local/scripts/libservice.sh
. /usr/local/scripts/libvalidations.sh

# 函数列表

# 加载应用使用的环境变量初始值，该函数在相关脚本中以 eval 方式调用
# 全局变量:
#   ENV_* : 容器使用的全局变量
#   APP_* : 在镜像创建时定义的全局变量
#   *_* : 应用配置文件使用的全局变量，变量名根据配置项定义
# 返回值:
#   可以被 'eval' 使用的序列化输出
app_env() {
    cat <<-'EOF'
		# Common Settings
		export ENV_DEBUG=${ENV_DEBUG:-false}

		# Application Authentication
		export JENKINS_USER=${JENKINS_USER:-jenkins}
EOF

    # 利用 *_FILE 设置密码，不在配置命令中设置密码，增强安全性
#    if [[ -f "${ZOO_CLIENT_PASSWORD_FILE:-}" ]]; then
#        cat <<"EOF"
#			export ZOO_CLIENT_PASSWORD="$(< "${ZOO_CLIENT_PASSWORD_FILE}")"
#EOF
#    fi
}

# 配置 libnss_wrapper 以使得 PostgreSQL 命令可以以任意用户身份执行
jenkins_enable_nss_wrapper() {
    SOCK_DOCKER_GID=`ls -ng /var/run/docker.sock | tr -s " " | cut -f3 -d' '`
    [ ! -e "${JENKINS_HOME}/nss_wrapper_passwd" ] && touch "${JENKINS_HOME}/nss_wrapper_passwd"
    [ ! -e "${JENKINS_HOME}/nss_wrapper_group" ] && touch "${JENKINS_HOME}/nss_wrapper_group"
    export NSS_WRAPPER_PASSWD="${JENKINS_HOME}/nss_wrapper_passwd"
    export NSS_WRAPPER_GROUP="${JENKINS_HOME}/nss_wrapper_group"
    if [ -e /usr/lib/libnss_wrapper.so ] && is_root ; then
        LOG_D "Configuring libnss_wrapper..."
        echo "jenkins:x:999:${SOCK_DOCKER_GID}:Jenkins:/srv/data:/bin/bash" > "${NSS_WRAPPER_PASSWD}"
        echo "jenkins:x:${SOCK_DOCKER_GID}:" > "${NSS_WRAPPER_GROUP}"    
    fi
    export LD_PRELOAD='/usr/lib/libnss_wrapper.so'
}

jenkins_disable_nss_wrapper() {
    # unset/cleanup "nss_wrapper" bits
    if [ "${LD_PRELOAD:-}" = '/usr/lib/libnss_wrapper.so' ] && is_root ; then
        rm -f "${NSS_WRAPPER_PASSWD}" "${NSS_WRAPPER_GROUP}"
        unset LD_PRELOAD NSS_WRAPPER_PASSWD NSS_WRAPPER_GROUP
    fi
}

# 设置环境变量 JVMFLAGS
# 参数:
#   $1 - value
jenkins_export_jvmflags() {
    local -r value="${1:?value is required}"

    export JVMFLAGS="${JVMFLAGS} ${value}"
    echo "export JVMFLAGS=\"${JVMFLAGS}\"" > "${APP_CONF_DIR}/java.env"
}

# 配置 HEAP 大小
# 参数:
#   $1 - HEAP 大小
jenkins_configure_heap_size() {
    local -r heap_size="${1:?heap_size is required}"

    if [[ "${JVMFLAGS}" =~ -Xm[xs].*-Xm[xs] ]]; then
        LOG_D "Using specified values (JVMFLAGS=${JVMFLAGS})"
    else
        LOG_D "Setting '-Xmx${heap_size}m -Xms${heap_size}m' heap options..."
        jenkins_export_jvmflags "-Xmx${heap_size}m -Xms${heap_size}m"
    fi
}

# 检测用户参数信息是否满足条件; 针对部分权限过于开放情况，打印提示信息
app_verify_minimum_env() {
    local error_code=0

    LOG_D "Validating settings in JENKINS_* env vars..."

    print_validation_error() {
        LOG_E "$1"
        error_code=1
    }

    # 检测认证设置。如果不允许匿名登录，检测登录用户名及密码是否设置
#    if is_boolean_yes "$ALLOW_ANONYMOUS_LOGIN"; then
#        LOG_W "You have set the environment variable ALLOW_ANONYMOUS_LOGIN=${ALLOW_ANONYMOUS_LOGIN}. For safety reasons, do not use this flag in a production environment."
#    elif ! is_boolean_yes "$ZOO_ENABLE_AUTH"; then
#        print_validation_error "The ZOO_ENABLE_AUTH environment variable does not configure authentication. Set the environment variable ALLOW_ANONYMOUS_LOGIN=yes to allow unauthenticated users to connect to ZooKeeper."
#    fi

    # TODO: 其他参数检测

    [[ "$error_code" -eq 0 ]] || exit "$error_code"
}

# 更改默认监听地址为 "*" 或 "0.0.0.0"，以对容器外提供服务；默认配置文件应当为仅监听 localhost(127.0.0.1)
app_enable_remote_connections() {
    LOG_D "Modify default config to enable all IP access"
	
}

# 检测依赖的服务端口是否就绪；该脚本依赖系统工具 'netcat'
# 参数:
#   $1 - host:port
app_wait_service() {
    local serviceport=${1:?Missing server info}
    local service=${serviceport%%:*}
    local port=${serviceport#*:}
    local retry_seconds=5
    local max_try=100
    let i=1

    if [[ -z "$(which nc)" ]]; then
        LOG_E "Nedd nc installed before, command: \"apt-get install netcat\"."
        exit 1
    fi

    LOG_I "[0/${max_try}] check for ${service}:${port}..."

    set +e
    nc -z ${service} ${port}
    result=$?

    until [ $result -eq 0 ]; do
      LOG_D "  [$i/${max_try}] not available yet"
      if (( $i == ${max_try} )); then
        LOG_E "${service}:${port} is still not available; giving up after ${max_try} tries."
        exit 1
      fi
      
      LOG_I "[$i/${max_try}] try in ${retry_seconds}s once again ..."
      let "i++"
      sleep ${retry_seconds}

      nc -z ${service} ${port}
      result=$?
    done

    set -e
    LOG_I "[$i/${max_try}] ${service}:${port} is available."
}

# 以后台方式启动应用服务，并等待启动就绪
app_start_server_bg() {
    is_app_server_running && return

    LOG_I "Starting ${APP_NAME} in background..."

	# 使用内置脚本启动服务
    #local start_command="zkServer.sh start"
    #if is_boolean_yes "${ENV_DEBUG}"; then
    #    $start_command &
    #else
    #    $start_command >/dev/null 2>&1 &
    #fi
	
	# 使用内置命令启动服务
	# if [[ "${ENV_DEBUG:-false}" = true ]]; then
    #    debug_execute "rabbitmq-server" &
    #else
    #    debug_execute "rabbitmq-server" >/dev/null 2>&1 &
    #fi

	# 通过命令或特定端口检测应用是否就绪
    LOG_I "Checking ${APP_NAME} ready status..."
    # wait-for-port --timeout 60 "$ZOO_PORT_NUMBER"

    LOG_D "${APP_NAME} is ready for service..."
}

# 停止应用服务
app_stop_server() {
    is_app_server_running || return
    LOG_I "Stopping ${APP_NAME}..."
    
    # 使用 PID 文件 kill 进程
    stop_service_using_pid "$APP_PID_FILE"

	# 使用内置命令停止服务
    #debug_execute "rabbitmqctl" stop

    # 使用内置脚本关闭服务
    #if [[ "$ENV_DEBUG" = true ]]; then
    #    "zkServer.sh" stop
    #else
    #    "zkServer.sh" stop >/dev/null 2>&1
    #fi

	# 检测停止是否完成
	local counter=10
    while [[ "$counter" -ne 0 ]] && is_app_server_running; do
        LOG_D "Waiting for ${APP_NAME} to stop..."
        sleep 1
        counter=$((counter - 1))
    done
}

# 检测应用服务是否在后台运行中
is_app_server_running() {
    LOG_D "Check if ${APP_NAME} is running..."
    local pid
    pid="$(get_pid_from_file '/var/run/${APP_NAME}/${APP_NAME}.pid')"

    if [[ -z "${pid}" ]]; then
        false
    else
        is_service_running "${pid}"
    fi
}

# 清理初始化应用时生成的临时文件
app_clean_tmp_file() {
    LOG_D "Clean ${APP_NAME} tmp files for init..."

}

# 在重新启动容器时，删除标志文件及必须删除的临时文件 (容器重新启动)
app_clean_from_restart() {
    LOG_D "Clean ${APP_NAME} tmp files for restart..."
    local -r -a files=(
        "/var/run/${APP_NAME}/${APP_NAME}.pid"
    )

    for file in ${files[@]}; do
        if [[ -f "$file" ]]; then
            LOG_I "Cleaning stale $file file"
            rm "$file"
        fi
    done
}

# 应用默认初始化操作
# 执行完毕后，生成文件 ${APP_CONF_DIR}/.app_init_flag 及 ${APP_DATA_DIR}/.data_init_flag 文件
app_default_init() {
	app_clean_from_restart
    LOG_D "Check init status of ${APP_NAME}..."

    # 检测配置文件是否存在
    if [[ ! -f "${APP_CONF_DIR}/.app_init_flag" ]]; then
        LOG_I "No injected configuration file found, creating default config files..."
        
        # TODO: 生成配置文件，并按照容器运行参数进行相应修改

        touch ${APP_CONF_DIR}/.app_init_flag
        echo "$(date '+%Y-%m-%d %H:%M:%S') : Init success." >> ${APP_CONF_DIR}/.app_init_flag
    else
        LOG_I "User injected custom configuration detected!"
    fi

    if [[ ! -f "${APP_DATA_DIR}/.data_init_flag" ]]; then
        LOG_I "Deploying ${APP_NAME} from scratch..."

		# 检测服务是否运行中如果未运行，则启动后台服务
        is_app_server_running || app_start_server_bg

        # TODO: 根据需要生成相应初始化数据

        touch ${APP_DATA_DIR}/.data_init_flag
        echo "$(date '+%Y-%m-%d %H:%M:%S') : Init success." >> ${APP_DATA_DIR}/.data_init_flag
    else
        LOG_I "Deploying ${APP_NAME} with persisted data..."
    fi
}

# 用户自定义的前置初始化操作，依次执行目录 preinitdb.d 中的初始化脚本
# 执行完毕后，生成文件 ${APP_DATA_DIR}/.custom_preinit_flag
app_custom_preinit() {
    LOG_D "Check custom pre-init status of ${APP_NAME}..."

    # 检测用户配置文件目录是否存在 preinitdb.d 文件夹，如果存在，尝试执行目录中的初始化脚本
    if [ -d "/srv/conf/${APP_NAME}/preinitdb.d" ]; then
        # 检测数据存储目录是否存在已初始化标志文件；如果不存在，检索可执行脚本文件并进行初始化操作
        if [[ -n $(find "/srv/conf/${APP_NAME}/preinitdb.d/" -type f -regex ".*\.\(sh\)") ]] && \
            [[ ! -f "${APP_DATA_DIR}/.custom_preinit_flag" ]]; then
            LOG_I "Process custom pre-init scripts from /srv/conf/${APP_NAME}/preinitdb.d..."

            # 检索所有可执行脚本，排序后执行
            find "/srv/conf/${APP_NAME}/preinitdb.d/" -type f -regex ".*\.\(sh\)" | sort | process_init_files

            touch ${APP_DATA_DIR}/.custom_preinit_flag
            echo "$(date '+%Y-%m-%d %H:%M:%S') : Init success." >> ${APP_DATA_DIR}/.custom_preinit_flag
            LOG_I "Custom preinit for ${APP_NAME} complete."
        else
            LOG_I "Custom preinit for ${APP_NAME} already done before, skipping initialization."
        fi
    fi

    # 检测依赖的服务是否就绪
    #for i in ${SERVICE_PRECONDITION[@]}; do
    #    app_wait_service "${i}"
    #done
}

# 用户自定义的应用初始化操作，依次执行目录initdb.d中的初始化脚本
# 执行完毕后，生成文件 ${APP_DATA_DIR}/.custom_init_flag
app_custom_init() {
    LOG_D "Check custom init status of ${APP_NAME}..."

    # 检测用户配置文件目录是否存在 initdb.d 文件夹，如果存在，尝试执行目录中的初始化脚本
    if [ -d "/srv/conf/${APP_NAME}/initdb.d" ]; then
    	# 检测数据存储目录是否存在已初始化标志文件；如果不存在，检索可执行脚本文件并进行初始化操作
    	if [[ -n $(find "/srv/conf/${APP_NAME}/initdb.d/" -type f -regex ".*\.\(sh\|sql\|sql.gz\)") ]] && \
            [[ ! -f "${APP_DATA_DIR}/.custom_init_flag" ]]; then
            LOG_I "Process custom init scripts from /srv/conf/${APP_NAME}/initdb.d..."

            # 检测服务是否运行中；如果未运行，则启动后台服务
            is_app_server_running || app_start_server_bg

            # 检索所有可执行脚本，排序后执行
    		find "/srv/conf/${APP_NAME}/initdb.d/" -type f -regex ".*\.\(sh\|sql\|sql.gz\)" | sort | while read -r f; do
                case "$f" in
                    *.sh)
                        if [[ -x "$f" ]]; then
                            LOG_D "Executing $f"; "$f"
                        else
                            LOG_D "Sourcing $f"; . "$f"
                        fi
                        ;;
                    #*.sql)    LOG_D "Executing $f"; postgresql_execute "$PG_DATABASE" "$PG_INITSCRIPTS_USERNAME" "$PG_INITSCRIPTS_PASSWORD" < "$f";;
                    #*.sql.gz) LOG_D "Executing $f"; gunzip -c "$f" | postgresql_execute "$PG_DATABASE" "$PG_INITSCRIPTS_USERNAME" "$PG_INITSCRIPTS_PASSWORD";;
                    *)        LOG_D "Ignoring $f" ;;
                esac
            done

            touch ${APP_DATA_DIR}/.custom_init_flag
    		echo "$(date '+%Y-%m-%d %H:%M:%S') : Init success." >> ${APP_DATA_DIR}/.custom_init_flag
    		LOG_I "Custom init for ${APP_NAME} complete."
    	else
    		LOG_I "Custom init for ${APP_NAME} already done before, skipping initialization."
    	fi
    fi

    # 检测服务是否运行中；如果运行，则停止后台服务
	is_app_server_running && app_stop_server

    # 删除第一次运行生成的临时文件
    app_clean_tmp_file

	# 绑定所有 IP ，启用远程访问
    app_enable_remote_connections
}

