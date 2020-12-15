# Ver: 1.4 by Endial Fang (endial@126.com)
#

# 预处理 =========================================================================
ARG registry_url="registry.cn-shenzhen.aliyuncs.com"
FROM ${registry_url}/colovu/dbuilder as builder

# sources.list 可使用版本：default / tencent / ustc / aliyun / huawei
ARG apt_source=aliyun

# 编译镜像时指定用于加速的本地服务器地址
ARG local_url=""

ENV APP_NAME=jenkins \
	APP_VERSION=2.235.5

# 选择软件包源(Optional)，以加速后续软件包安装
RUN select_source ${apt_source};

# 安装依赖的软件包及库(Optional)
#RUN install_pkg xz-utils

# 下载并解压软件包
RUN set -eux; \
	appVersion=3.6.3; \
	appName="apache-maven-${appVersion}-bin.tar.gz"; \
	[ ! -z ${local_url} ] && localURL=${local_url}/maven; \
	appUrls="${localURL:-} \
		https://mirrors.bfsu.edu.cn/apache/maven/maven-3/${appVersion}/binaries \
		https://downloads.apache.org/maven/maven-3/${appVersion}/binaries \
		https://mirrors.tuna.tsinghua.edu.cn/apache/maven/maven-3/${appVersion}/binaries \
		"; \
	download_pkg unpack ${appName} "${appUrls}";

# 下载并解压软件包
RUN set -eux; \
	appName="${APP_NAME}-war-${APP_VERSION}.war"; \
	[ ! -z ${local_url} ] && localURL=${local_url}/jenkins; \
	appUrls="${localURL:-} \
		https://repo.jenkins-ci.org/public/org/jenkins-ci/main/jenkins-war/${APP_VERSION} \
		"; \
	download_pkg install ${appName} "${appUrls}"; \
	mv "/usr/local/bin/${APP_NAME}-war-${APP_VERSION}.war" "/usr/local/bin/${APP_NAME}.war";

# Alpine: scanelf --needed --nobanner --format '%n#p' --recursive /usr/local | tr ',' '\n' | sort -u | awk 'system("[ -e /usr/local/lib/" $1 " ]") == 0 { next } { print "so:" $1 }'
# Debian: find /usr/local/redis/bin -type f -executable -exec ldd '{}' ';' | awk '/=>/ { print $(NF-1) }' | sort -u | xargs -r dpkg-query --search | cut -d: -f1 | sort -u


# 镜像生成 ========================================================================
FROM ${registry_url}/colovu/openjre:8

# sources.list 可使用版本：default / tencent / ustc / aliyun / huawei
ARG apt_source=aliyun

# 编译镜像时指定用于加速的本地服务器地址
ARG local_url=""

ARG maven_ver=3.6.3

ENV APP_NAME=jenkins \
	APP_USER=jenkins \
	APP_EXEC=jenkins.sh \
	APP_VERSION=2.235.5

ENV	APP_HOME_DIR=/usr/share/${APP_NAME} \
	APP_DEF_DIR=/etc/${APP_NAME} \
	APP_CONF_DIR=/srv/conf/${APP_NAME} \
	APP_DATA_DIR=/srv/data/${APP_NAME} \
	APP_DATA_LOG_DIR=/srv/datalog/${APP_NAME} \
	APP_CACHE_DIR=/var/cache/${APP_NAME} \
	APP_RUN_DIR=/var/run/${APP_NAME} \
	APP_LOG_DIR=/var/log/${APP_NAME} \
	APP_CERT_DIR=/srv/cert/${APP_NAME} 

ENV	MAVEN_HOME_DIR=/usr/local/maven \
	JENKINS_WAR=${APP_HOME_DIR}/jenkins.war \
	JENKINS_HOME=/var/jenkins_home \
	JENKINS_SLAVE_AGENT_PORT=50000 \
	JENKINS_VERSION=${APP_VERSION} 

ENV JENKINS_UC_EXPERIMENTAL=https://updates.jenkins.io/experimental \
	COPY_REFERENCE_FILE_LOG=${JENKINS_HOME}/copy_reference_file.log \
	REF=${APP_HOME_DIR}/ref \
	JENKINS_UC=https://updates.jenkins-zh.cn \
	JENKINS_UC_DOWNLOAD=https://mirrors.tuna.tsinghua.edu.cn/jenkins
#	JENKINS_UC=https://updates.jenkins.io \
#	JENKINS_OPTS="-Djenkins.install.runSetupWizard=false"
#	JENKINS_OPTS="-Djava.awt.headless=true"
#	CATALINA_OPTS="-Djava.awt.headless=true"

ENV PATH="${MAVEN_HOME_DIR}/bin:${APP_HOME_DIR}:${PATH}"

LABEL \
	"Version"="v${APP_VERSION}" \
	"Description"="Docker image for ${APP_NAME}(v${APP_VERSION})." \
	"Dockerfile"="https://github.com/colovu/docker-${APP_NAME}" \
	"Vendor"="Endial Fang (endial@126.com)"

# 应用健康状态检查
HEALTHCHECK CMD wget -O- -q http://localhost:8080/login >/dev/null || exit 1

COPY customer /

# 以包管理方式安装软件包(Optional)
RUN select_source ${apt_source}
RUN install_pkg wget curl ca-certificates bzr netbase git mercurial openssh-client subversion procps bzip2 unzip xz-utils
RUN install_pkg psmisc ant libfreetype6 libncurses6
#RUN install_pkg daemon ruby rbenv libgpm2 libprocps7 make net-tools ca-certificates-java

RUN create_user && prepare_env

# 从预处理过程中拷贝软件包(Optional)
COPY --from=builder /usr/local/apache-maven-${maven_ver}/ /usr/local/maven
COPY --from=builder /usr/local/bin/jenkins.war /usr/share/jenkins/jenkins.war

# 执行预处理脚本，并验证安装的软件包
RUN set -eux; \
	override_file="/usr/local/overrides/overrides-${APP_VERSION}.sh"; \
	[ -e "${override_file}" ] && /bin/bash "${override_file}"; \
# 验证安装的软件是否可以正常运行，常规情况下放置在命令行的最后
	gosu ${APP_NAME} mvn -v ; \
	:;

# 默认提供的数据卷
VOLUME ["/srv/conf", "/srv/data", "/srv/datalog", "/srv/cert", "/var/log"]

# 默认使用gosu切换为新建用户启动，必须保证端口在1024之上
EXPOSE 8080 50000

# 容器初始化命令，默认存放在：/usr/local/bin/entry.sh
ENTRYPOINT ["entry.sh"]

# 应用程序的服务命令，必须使用非守护进程方式运行。如果使用变量，则该变量必须在运行环境中存在（ENV可以获取）
#CMD ["${APP_EXEC}", "-jar", "${APP_HOME_DIR}/jenkins.war"]
CMD ["jenkins.sh"]
