#!/bin/bash
set -euo pipefail  # 开启严格模式，遇到错误立即退出

# ===================== 配置项 =====================
# Harbor 服务器地址（含端口，无需加http://前缀）
HARBOR_REGISTRY="120.78.146.230:9090"
# Harbor 项目名称（需提前在Harbor中创建）
HARBOR_PROJECT="library"
# Harbor 登录账号
HARBOR_USER="admin"
# Harbor 登录密码（可改为手动输入，见注释）
HARBOR_PASSWORD="Harbor12345"
# 是否清理本地新增的Harbor标签（true/false）
CLEAN_TAG_AFTER_PUSH="true"
# 镜像大小阈值（MB），超过该值则跳过推送（1GB = 1024MB）
IMAGE_SIZE_THRESHOLD_MB=1024
# 冒号替换字符（处理含冒号的镜像仓库名称）
COLON_REPLACE_CHAR="-"
# ==================================================

# 函数：打印带颜色的日志
log_info() {
  echo -e "\033[32m[INFO] $1\033[0m"
}

log_warn() {
  echo -e "\033[33m[WARN] $1\033[0m"
}

log_error() {
  echo -e "\033[31m[ERROR] $1\033[0m"
  exit 1
}

# 函数：检查Docker是否运行
check_docker() {
  if ! docker info >/dev/null 2>&1; then
    log_error "Docker 未运行或当前用户无Docker操作权限，请检查Docker服务和用户权限"
  fi
}

# 函数：登录Harbor
login_harbor() {
  log_info "开始登录Harbor服务器: ${HARBOR_REGISTRY}"
  if echo "${HARBOR_PASSWORD}" | docker login "${HARBOR_REGISTRY}" -u "${HARBOR_USER}" --password-stdin; then
    log_info "Harbor登录成功"
  else
    log_error "Harbor登录失败，请检查账号、密码或服务器地址"
  fi
}

# 修复后的函数：获取镜像大小（强制转换为整数MB，四舍五入）
# 参数：镜像名称（如nginx:latest）
get_image_size_mb() {
  local local_image=$1
  # 获取镜像的原始大小（如2.4GB、512MB、1024KB）
  local size_str=$(docker images --format "{{.Size}}" "${local_image}" | head -n1)
  # 空值处理
  if [ -z "${size_str}" ]; then
    log_warn "镜像${local_image}的大小获取失败，默认按0MB处理"
    echo 0
    return
  fi
  # 提取数字和单位（使用正则匹配，兼容小数和整数）
  local size_num=$(echo "${size_str}" | sed -E 's/^([0-9]+\.?[0-9]*)([BKMG])B?$/\1/')
  local size_unit=$(echo "${size_str}" | sed -E 's/^([0-9]+\.?[0-9]*)([BKMG])B?$/\2/')

  # 数字合法性校验
  if ! echo "${size_num}" | grep -E '^[0-9]+\.?[0-9]*$' >/dev/null 2>&1; then
    log_warn "无法识别镜像大小数字: ${size_str}，默认按0MB处理"
    echo 0
    return
  fi

  # 根据单位转换为MB，并四舍五入为整数
  local size_mb=0
  case "${size_unit}" in
    B)
      size_mb=$(echo "scale=0; ${size_num} / 1024 / 1024 + 0.5" | bc)
      ;;
    K)
      size_mb=$(echo "scale=0; ${size_num} / 1024 + 0.5" | bc)
      ;;
    M)
      size_mb=$(echo "scale=0; ${size_num} + 0.5" | bc)
      ;;
    G)
      size_mb=$(echo "scale=0; ${size_num} * 1024 + 0.5" | bc)
      ;;
    *)
      log_warn "无法识别镜像大小单位: ${size_str}，默认按0MB处理"
      size_mb=0
      ;;
  esac
  # 确保输出为整数（防止bc异常输出）
  echo "${size_mb}" | awk '{print int($1)}'
}

# 修复后的函数：获取本地所有Docker镜像（过滤<none>、Harbor标签、含无效字符的异常镜像）
get_local_images() {
  # 1. 过滤<none>标签 2. 排除以Harbor地址开头的镜像（避免重复处理） 3. 输出仓库:标签
  docker images --format "{{.Repository}}:{{.Tag}}" | \
    grep -v "<none>" | \
    grep -v "^${HARBOR_REGISTRY}/" || true
}

# 新增函数：清理镜像仓库名称中的非法字符（主要是冒号）
# 参数：原始仓库名称
clean_repo_name() {
  local raw_repo=$1
  # 将冒号替换为配置的合法字符，保留其他字符
  echo "${raw_repo}" | sed "s/:/${COLON_REPLACE_CHAR}/g"
}

# 修复后的函数：推送镜像到Harbor（含大小判断、非法字符处理）
push_image_to_harbor() {
  local local_image=$1

  # 第一步：获取镜像大小并判断是否超过阈值
  local size_mb=$(get_image_size_mb "${local_image}")
  # 再次校验大小是否为整数
  if ! echo "${size_mb}" | grep -E '^[0-9]+$' >/dev/null 2>&1; then
    log_warn "镜像${local_image}的大小转换异常，跳过推送"
    return
  fi
  # 跳过0MB的无效镜像
  if [ "${size_mb}" -eq 0 ]; then
    log_warn "镜像大小为0MB，跳过推送: ${local_image}"
    return
  fi
  if [ "${size_mb}" -gt "${IMAGE_SIZE_THRESHOLD_MB}" ]; then
    log_warn "镜像大小(${size_mb}MB)超过阈值(${IMAGE_SIZE_THRESHOLD_MB}MB)，跳过推送: ${local_image}"
    return  # 跳过当前镜像，继续下一个
  fi

  # 第二步：拆分镜像仓库和标签（处理无标签的情况，默认latest）
  local raw_repo=$(echo "${local_image}" | cut -d: -f1)
  local tag=$(echo "${local_image}" | cut -d: -f2- || "latest")
  # 若拆分后标签包含冒号（如原始镜像为IP:PORT/repo:tag），修正标签为latest（避免多冒号解析错误）
  if echo "${tag}" | grep -q ":"; then
    tag="latest"
    log_warn "镜像${local_image}的标签含冒号，自动修正为latest"
  fi

  # 第三步：清理仓库名称中的非法字符
  local clean_repo=$(clean_repo_name "${raw_repo}")

  # 第四步：构建合法的Harbor镜像标签
  local harbor_image="${HARBOR_REGISTRY}/${HARBOR_PROJECT}/${clean_repo}:${tag}"

  log_info "为镜像打标签: ${local_image} -> ${harbor_image} (大小: ${size_mb}MB)"
  docker tag "${local_image}" "${harbor_image}"

  log_info "推送镜像到Harbor: ${harbor_image}"
  if docker push "${harbor_image}"; then
    log_info "镜像推送成功: ${harbor_image}"
    # 可选：清理本地新增的Harbor标签
    if [ "${CLEAN_TAG_AFTER_PUSH}" = "true" ]; then
      docker rmi "${harbor_image}" >/dev/null 2>&1
      log_info "已清理本地临时标签: ${harbor_image}"
    fi
  else
    log_error "镜像推送失败: ${harbor_image}"
  fi
}

# 主流程
main() {
  # 前置检查
  check_docker

  # 登录Harbor
  login_harbor

  # 获取本地镜像列表
  local images=$(get_local_images)
  if [ -z "${images}" ]; then
    log_warn "本地无有效Docker镜像（已过滤<none>、Harbor标签镜像）"
    exit 0
  fi

  # 批量推送镜像
  log_info "开始批量推送本地镜像到Harbor，共找到 $(echo "${images}" | wc -l) 个镜像（阈值: ${IMAGE_SIZE_THRESHOLD_MB}MB）"
  for image in ${images}; do
    push_image_to_harbor "${image}"
  done

  log_info "所有镜像推送流程执行完成！"
  # 退出Harbor登录
  docker logout "${HARBOR_REGISTRY}" >/dev/null 2>&1
}

# 执行主流程
main
