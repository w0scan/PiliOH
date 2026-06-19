#!/bin/bash

# 参数处理
Arg="$1"

# 错误处理
set -e
trap 'echo "Prebuild Error: $BASH_COMMAND failed on line $LINENO"; exit 1' ERR

# 获取版本信息
versionCode=$(git rev-list --count HEAD | tr -d '\n')
commitHash=$(git rev-parse HEAD | tr -d '\n')

# 处理 pubspec.yaml
versionName=""
temp_file=$(mktemp)

while IFS= read -r line || [ -n "$line" ]; do
    if [[ "$line" =~ ^[[:space:]]*version:[[:space:]]*([[:digit:]]+\.[[:digit:]]+\.[[:digit:]]+) ]]; then
        versionName="${BASH_REMATCH[1]}"
        if [[ "$Arg" == "android" ]]; then
            versionName="${versionName}-${commitHash:0:9}"
        fi
        echo "version: ${versionName}+${versionCode}"
    else
        echo "$line"
    fi
done < "pubspec.yaml" > "$temp_file"

# 检查是否找到版本
if [[ -z "$versionName" ]]; then
    echo "version not found" >&2
    exit 1
fi

# 更新 pubspec.yaml
mv "$temp_file" "pubspec.yaml"

# 生成构建信息
buildTime=$(date +%s)

cat > pili_release.json << EOF
{"pili.name":"${versionName}","pili.code":${versionCode},"pili.hash":"${commitHash}","pili.time":${buildTime}}
EOF

# 设置 GitHub Actions 环境变量
if [[ -n "$GITHUB_ENV" ]]; then
    echo "version=${versionName}+${versionCode}" >> "$GITHUB_ENV"
fi

echo "Build version: ${versionName}+${versionCode}"