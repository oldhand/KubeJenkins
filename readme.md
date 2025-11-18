# KubeJenkins 部署指南

## 概述

本项目包含一系列Ansible角色，用于在Kubernetes环境中自动化部署和管理核心服务组件，包括Jenkins、Harbor、WebSSH2和Gitea。各角色采用标准化部署流程，确保环境一致性和可维护性，支持离线部署场景。


## 角色列表

1. **jenkins**  
   部署Jenkins CI/CD平台，提供自动化构建、测试和部署能力。默认通过NodePort 30101暴露服务，包含镜像准备、历史资源清理、存储配置、插件部署及管理员账号初始化等功能。

2. **harbor**  
   部署Harbor容器镜像仓库，用于镜像存储、版本管理和安全扫描。通过Helm完成部署，自动创建所需命名空间、存储卷（数据库、Redis等），并等待所有组件就绪。

3. **webssh2**  
   部署WebSSH2网页SSH终端，支持通过浏览器访问集群节点。以DaemonSet方式部署在terminal-system命名空间，通过NodePort 30102提供服务，包含配置文件管理和历史资源清理。

4. **gitea**  
   部署Gitea代码仓库，支持Git版本控制和团队协作。默认通过NodePort 30103暴露服务，包含存储配置、SMTP密钥管理及Helm部署流程，数据存储在节点`/data`目录。


## 前置要求

1. **Kubernetes集群**
    - 最低版本要求：v1.29.0+
    - 集群状态：所有节点处于`Ready`状态（可通过`kubectl get nodes`验证）
    - 节点资源：单节点至少2核4G内存，支持单节点集群（同时作为控制节点和工作节点）
    - 存储要求：集群已配置默认存储类（如NFS、LocalPV），或节点`/data`目录预留至少100GB可用空间（用于数据持久化）
    - 网络要求：节点开放30101-30103端口（NodePort范围）及组件通信所需端口（如Harbor的443、5000等）

2. **工具依赖**
    - Helm：v3.0.0+（已安装在部署节点，用于Harbor和Gitea的Chart部署）
    - Ansible：2.10+（部署节点已安装，且能通过SSH访问目标节点）
    - kubectl：与Kubernetes集群版本兼容（部署节点已配置kubeconfig，能正常操作集群）
    - 容器运行时：节点已安装Docker 20.10+或containerd 1.6+，且状态正常
    - 辅助工具：节点需安装`curl`、`tar`、`chrony`（时间同步），确保环境一致性


## 部署步骤

1. **环境检查**
    - 验证Kubernetes集群状态：`kubectl get nodes`（确认节点为`Ready`）
    - 验证Helm版本：`helm version`（确保输出Client版本≥v3.0.0）
    - 测试Ansible连接：`ansible k8s -i hosts.ini -m ping`（确认节点可访问）
    - 检查存储目录：`ansible k8s -i hosts.ini -a "df -h /data"`（确认可用空间充足）

2. **配置准备**
    - 克隆项目至部署节点：`git clone <项目仓库地址>`
    - 进入项目根目录：`cd <项目目录>`
    - **配置hosts.ini**（关键步骤）：  
      编辑项目根目录下的`hosts.ini`文件，单节点集群配置示例：
      ```ini
      [k8s]
      192.168.0.139  is_master=1  is_worker=1  is_init=1  ansible_user="root"  ansible_password=""  ansible_ssh_common_args="-o StrictHostKeyChecking=no"
      ```  
      参数说明：
        - `[k8s]`：节点组名称（与部署脚本匹配，不可随意修改）
        - `192.168.0.139`：目标节点IP地址
        - `is_master=1`：标记为控制节点
        - `is_worker=1`：标记为工作节点（单节点需同时开启）
        - `is_init=1`：标记为初始化节点（集群唯一）
        - `ansible_user`：SSH登录用户名（默认root）
        - `ansible_password`：SSH登录密码（为空时使用密钥认证）
        - `ansible_ssh_common_args`：禁用SSH主机密钥检查（首次连接无需手动确认）
    - 根据需求修改角色配置（可选）：
        - 角色参数：修改`roles/<角色名>/templates/`下的配置模板
    - 离线环境准备：将镜像包（`.tar`或分卷文件）放入对应角色的`files/`目录

3. **执行部署**
    - 赋予部署脚本执行权限：`chmod +x install.sh`
    - 运行部署脚本：`./install.sh`（脚本会自动读取`hosts.ini`作为 inventory）
    - 脚本执行过程中会显示各角色部署进度，最终输出"All components deployed successfully"表示部署完成


## 访问与验证

### 1. Jenkins验证
- **访问地址**：`http://192.168.0.139:30101`
- **验证步骤**：
    1. 获取管理员密码：`kubectl exec -n kubejenkins $(kubectl get pods -n kubejenkins -l app=jenkins -o jsonpath='{.items[0].metadata.name}') -- cat /var/jenkins_home/secrets/initialAdminPassword`
    2. 登录控制台，完成插件初始化，确认界面无报错
    3. 验证功能：创建测试任务并执行，确认构建流程正常

### 2. Harbor验证
- **访问地址**：`https://192.168.0.139:<harbor-nodePort>`（端口查询：`kubectl get svc -n harbor`）
- **验证步骤**：
    1. 使用初始账号`admin`及配置的密码登录
    2. 配置Docker信任仓库：在节点`/etc/docker/daemon.json`添加`"insecure-registries": ["192.168.0.139:<端口>"]`，重启Docker
    3. 测试推送：`docker tag hello-world 192.168.0.139:<端口>/test/hello-world && docker push 192.168.0.139:<端口>/test/hello-world`，确认推送成功

### 3. WebSSH2验证
- **访问地址**：`http://192.168.0.139:30102`
- **验证步骤**：
    1. 在登录界面输入节点IP（192.168.0.139）、SSH端口（默认22）、用户名和密码
    2. 执行`kubectl get namespaces`，确认能正常返回集群命名空间信息

### 4. Gitea验证
- **访问地址**：`http://192.168.0.139:30103`
- **验证步骤**：
    1. 首次访问创建管理员账号，完成初始化
    2. 创建测试仓库（如`test-repo`），通过`git clone http://192.168.0.139:30103/<用户名>/test-repo.git`验证克隆功能
    3. 提交测试文件并推送，确认版本控制正常


## 部署流程说明

所有角色通过`install.sh`脚本统一调度，遵循以下步骤：
1. **镜像准备**：检查并加载本地Docker镜像（支持分卷文件合并与解压，适配离线环境）
2. **历史清理**：删除指定服务的旧有Kubernetes资源（确保部署环境干净）
3. **服务部署**：创建命名空间、存储资源（PV/PVC）、配置文件，部署核心组件并等待就绪


## 注意事项

- `hosts.ini`中`[k8s]`节点组名称不可修改，否则部署脚本无法识别目标节点
- 单节点集群需同时设置`is_master=1`和`is_worker=1`，否则组件可能部署失败
- 若使用密钥认证，需确保部署节点的`~/.ssh/id_rsa`公钥已添加至目标节点的`~/.ssh/authorized_keys`
- 服务默认通过NodePort暴露，端口映射：Jenkins(30101)、WebSSH2(30102)、Gitea(30103)
- 所有数据默认存储在节点`/data`目录，建议定期备份该目录
- 部署失败时，可通过`kubectl logs <pod名称> -n <命名空间>`或`deploy.log`日志文件排查问题
- 如需重新部署，直接执行`./install.sh`即可，脚本会自动清理历史资源后重新部署