# Jenkins

针对 [Jenkins](https://www.jenkins.io/) 应用的 Docker 镜像，用于提供 Jenkins 服务。该镜像中同时安装了依赖的[Maven](http://maven.apache.org/index.html)组件。

使用说明可参照：[官方说明](https://www.jenkins.io/doc/)

![jenkins-logo](img/jenkins-logo.png)

**版本信息**：

- LTS、latest (2.235.5)

**镜像信息**

* 镜像地址：colovu/jenkins:latest



## **TL;DR**

Docker 快速启动命令：

```shell
$ docker run -d colovu/jenkins
```

Docker-Compose 快速启动命令：

```shell
$ curl -sSL https://raw.githubusercontent.com/colovu/docker-jenkins/master/docker-compose.yml > docker-compose.yml

$ docker-compose up -d
```



---



## 默认对外声明

### 端口

- 8080：Web访问端口
- 50000：Agent访问端口

### 数据卷

镜像默认提供以下数据卷定义，默认数据分别存储在自动生成的应用名对应`Jenkins`子目录中：

```shell
/var/datalog        # 数据操作日志文件
/srv/conf           # 配置文件
/srv/data           # 数据文件，主要存放应用数据
/var/log            # 日志输出
/var/run            # 系统运行时文件，如 PID 文件
```

如果需要持久化存储相应数据，需要**在宿主机建立本地目录**，并在使用镜像初始化容器时进行映射。宿主机相关的目录中如果不存在对应应用`Jenkins`的子目录或相应数据文件，则容器会在初始化时创建相应目录及文件。



## 容器配置

在初始化 `Jenkins` 容器时，如果没有预置配置文件，可以在命令行中设置相应环境变量对默认参数进行修改。类似命令如下：

```shell
$ docker run -d -e "APP_INIT_LIMIT=10" --name jenkins colovu/jenkins:latest
```



### 常规配置参数

常规配置参数用来配置容器基本属性，一般情况下需要设置，主要包括：

- 

### 常规可选参数

如果没有必要，可选配置参数可以不用定义，直接使用对应的默认值，主要包括：

- `ENV_DEBUG`：默认值：**false**。设置是否输出容器调试信息。可选值：1、true、yes

### 集群配置参数

配置服务为集群工作模式时，通过以下参数进行配置：

- 

### TLS配置参数

配置服务使用 TLS 加密时，通过以下参数进行配置：

- 



## 安全

### 用户及密码

`Jenkins`镜像默认禁用了无密码访问功能，在实际生产环境中建议使用用户名及密码控制访问；如果为了测试需要，可以使用以下环境变量启用无密码访问功能：

```shell
ALLOW_EMPTY_PASSWORD=yes
```

通过配置环境变量`APPNAME_PASSWORD`，可以启用基于密码的用户认证功能。命令行使用参考：

```shell
$ docker run -d -e APPNAME_PASSWORD=colovu colovu/jenkins:latest
```

使用 Docker-Compose 时，`docker-compose.yml`应包含类似如下配置：

```yaml
services:
  jenkins:
  ...
    environment:
      - APPNAME_PASSWORD=colovu
  ...
```

### 容器安全

本容器默认使用应用对应的运行时用户及用户组运行应用，以加强容器的安全性。在使用非`root`用户运行容器时，相关的资源访问会受限；应用仅能操作镜像创建时指定的路径及数据。使用`Non-root`方式的容器，更适合在生产环境中使用。



## 注意事项

- 容器中启动参数不能配置为后台运行，如果应用使用后台方式运行，则容器的启动命令会在运行后自动退出，从而导致容器退出；只能使用前台运行方式，如：`daemonize no`



## 更新记录

- LTS (2.235.5)、latest



----

本文原始来源 [Endial Fang](https://github.com/colovu) @ [Github.com](https://github.com)
