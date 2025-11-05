#!/bin/bash

# 定义需要下载的插件列表（从文件名中提取，去掉.jpi后缀）
plugins=(
  "antisamy-markup-formatter"
  "apache-httpcomponents-client-4-api"
  "asm-api"
  "bootstrap5-api"
  "bouncycastle-api"
  "caffeine-api"
  "checks-api"
  "commons-lang3-api"
  "commons-text-api"
  "credentials-binding"
  "credentials"
  "display-url-api"
  "echarts-api"
  "font-awesome-api"
  "git-client"
  "gitee"
  "git"
  "gson-api"
  "instance-identity"
  "ionicons-api"
  "jackson2-api"
  "jakarta-activation-api"
  "jakarta-mail-api"
  "jakarta-xml-bind-api"
  "javax-activation-api"
  "jaxb"
  "jquery3-api"
  "json-api"
  "junit"
  "mailer"
  "matrix-project"
  "mina-sshd-api-common"
  "mina-sshd-api-core"
  "plain-credentials"
  "plugin-util-api"
  "prism-api"
  "scm-api"
  "script-security"
  "snakeyaml-api"
  "ssh-credentials"
  "structs"
  "variant"
  "workflow-api"
  "workflow-job"
  "workflow-scm-step"
  "workflow-step-api"
  "workflow-support"
)

# 下载目录（当前目录，可自定义）
download_dir="./roles/jenkins/files"
mkdir -p "$download_dir" || { echo "创建目录失败"; exit 1; }

# 循环下载插件
for plugin in "${plugins[@]}"; do
  # 插件下载URL（latest指向最新版本）
  url="https://updates.jenkins.io/latest/${plugin}.hpi"
  # 保存文件名（保持.jpi后缀，与原格式一致）
  filename="${download_dir}/${plugin}.hpi"

  echo "正在下载: $plugin"
  if wget -q -O "$filename" "$url"; then
    echo "  下载成功: $filename"
  else
    echo "  下载失败: $plugin（URL: $url）"
  fi
done

echo "所有插件下载完成，保存目录: $download_dir"
