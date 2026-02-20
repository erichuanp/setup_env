#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 打印函数
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检测操作系统
OS_TYPE=""
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    OS_TYPE="Linux"
elif [[ "$OSTYPE" == "darwin"* ]]; then
    OS_TYPE="macOS"
elif [[ "$OSTYPE" == "cygwin"* || "$OSTYPE" == "msys"* || "$OSTYPE" == "win32" ]]; then
    OS_TYPE="Windows"
else
    print_error "不支持的操作系统: $OSTYPE"
    exit 1
fi
print_info "检测到操作系统: $OS_TYPE"

# 检查并安装 curl
if ! command -v curl &> /dev/null; then
    print_warn "curl 未安装，正在安装..."
    if [[ "$OS_TYPE" == "Linux" ]]; then
        if command -v apt &> /dev/null; then
            sudo apt update && sudo apt install -y curl
        elif command -v yum &> /dev/null; then
            sudo yum install -y curl
        elif command -v dnf &> /dev/null; then
            sudo dnf install -y curl
        elif command -v pacman &> /dev/null; then
            sudo pacman -S --noconfirm curl
        else
            print_error "无法识别的包管理器，请手动安装 curl"
            exit 1
        fi
    elif [[ "$OS_TYPE" == "macOS" ]]; then
        brew install curl
    fi
else
    print_info "curl 已安装"
fi

# 测试 GitHub 连接
print_info "正在测试 GitHub 连接..."
if ! curl -s --connect-timeout 5 https://github.com > /dev/null; then
    print_error "访问 GitHub 失败，请添加代理后再试"
    exit 1
fi
print_info "GitHub 连接正常"

# 检测并设置 UTF-8 locale
print_info "检测系统 locale 支持..."
SELECTED_LOCALE=""

# 获取系统支持的 locale 列表
if command -v locale &> /dev/null; then
    available_locales=$(locale -a 2>/dev/null)

    # 优先选择 en_US.UTF-8
    if echo "$available_locales" | grep -qi "^en_US\.utf8\|^en_US\.UTF-8"; then
        SELECTED_LOCALE="en_US.UTF-8"
        print_info "使用 locale: en_US.UTF-8"
    # 其次选择 C.UTF-8
    elif echo "$available_locales" | grep -qi "^C\.utf8\|^C\.UTF-8"; then
        SELECTED_LOCALE="C.UTF-8"
        print_warn "en_US.UTF-8 不可用，使用 C.UTF-8"
    # 尝试查找其他 UTF-8 locale
    else
        SELECTED_LOCALE=$(echo "$available_locales" | grep -i "utf8\|UTF-8" | head -n 1)
        if [[ -n "$SELECTED_LOCALE" ]]; then
            print_warn "使用可用的 UTF-8 locale: $SELECTED_LOCALE"
        else
            print_error "系统未找到任何 UTF-8 locale，可能需要手动配置"
            SELECTED_LOCALE="en_US.UTF-8"  # 默认值
        fi
    fi
else
    print_warn "无法检测 locale，使用默认值 en_US.UTF-8"
    SELECTED_LOCALE="en_US.UTF-8"
fi

# 检测当前 Shell
CURRENT_SHELL=$(ps -p $$ -o comm=)
print_info "当前 Shell: $CURRENT_SHELL"

retry_cmd() {
    local max_retries=3
    local delay=5
    local attempt=1

    while true; do
        "$@" && return 0
        if (( attempt >= max_retries )); then
            print_error "命令执行失败：$* （已重试 ${max_retries} 次）"
            return 1
        fi
        print_warn "命令执行失败，${delay} 秒后重试（第 ${attempt}/${max_retries} 次）: $*"
        attempt=$((attempt + 1))
        sleep "$delay"
    done
}

# ============================================
# SSH 和 Git 配置部分
# ============================================

print_info "开始配置 SSH 和 Git..."

# 0. 检查是否存在 ~/.ssh/.git
if [ -d "$HOME/.ssh/.git" ]; then
    print_info "检测到 ~/.ssh/.git 已存在，直接同步配置..."
    cd "$HOME/.ssh" || exit 1
    if retry_cmd git pull; then
        chmod 700 "$HOME/.ssh"
        chmod 600 "$HOME/.ssh"/* 2>/dev/null
        print_info "SSH配置已同步"
    else
        print_error "SSH 配置同步失败"
    fi
else
    # 1. 安装 git
    if ! command -v git &> /dev/null; then
        print_warn "git 未安装，正在安装..."
        if [[ "$OS_TYPE" == "Linux" ]]; then
            if command -v apt &> /dev/null; then
                sudo apt update && sudo apt install -y git
            elif command -v yum &> /dev/null; then
                sudo yum install -y git
            elif command -v dnf &> /dev/null; then
                sudo dnf install -y git
            elif command -v pacman &> /dev/null; then
                sudo pacman -S --noconfirm git
            fi
        elif [[ "$OS_TYPE" == "macOS" ]]; then
            brew install git
        fi
    else
        print_info "git 已安装"
    fi

    # 2. 设置 git global config
    print_info "配置 Git 全局设置..."
    git config --global user.name "erichuanp"
    git config --global user.email "erichuanp@gmail.com"
    print_info "Git 用户名: $(git config --global user.name)"
    print_info "Git 邮箱: $(git config --global user.email)"

    # 3. 检查并创建 ~/.ssh 文件夹
    if [ ! -d "$HOME/.ssh" ]; then
        print_info "创建 ~/.ssh 目录..."
        mkdir -p "$HOME/.ssh"
        chmod 700 "$HOME/.ssh"
    else
        print_info "~/.ssh 目录已存在"
    fi

    # 4. 检查并生成 SSH 密钥
    SSH_KEY_PATH="$HOME/.ssh/id_rsa"
    if [ ! -f "$SSH_KEY_PATH" ] && [ ! -f "$SSH_KEY_PATH.pub" ]; then
        print_info "未检测到 SSH 密钥，正在生成..."
        ssh-keygen -t rsa -b 4096 -C "erichuanp@gmail.com" -f "$SSH_KEY_PATH" -N ""
        print_info "SSH 密钥生成完成"
    else
        print_info "SSH 密钥已存在"
    fi

    # 5. 打印密钥并等待用户添加到 GitHub
    echo ""
    echo -e "${YELLOW}========================================${NC}"
    echo -e "${YELLOW}请登录 GitHub${NC}"
    echo -e "${GREEN}https://github.com/settings/keys${NC}"
    echo -e "${YELLOW}将以下密钥添加到受信 SSH Key 中：${NC}"
    echo -e "${YELLOW}========================================${NC}"
    echo ""
    cat "$SSH_KEY_PATH.pub"
    echo ""
    echo -e "${YELLOW}========================================${NC}"
    echo -n -e "${YELLOW}添加完成后按下 Enter 键继续...${NC}"
    read -r

    # 6. 在 ~/.ssh/ 里初始化 git 仓库并添加远程仓库
    print_info "初始化 ~/.ssh Git 仓库..."
    cd "$HOME/.ssh" || exit 1
    
    if [ ! -d ".git" ]; then
        git init
        print_info "Git 仓库初始化完成"
    fi

    # 检查是否已存在 origin
    if git remote | grep -q "^origin$"; then
        print_info "远程仓库 origin 已存在，更新 URL..."
        git remote set-url origin git@github.com:erichuanp/ssh_settings.git
    else
        print_info "添加远程仓库..."
        git remote add origin git@github.com:erichuanp/ssh_settings.git
    fi

    # 7. 拉取配置并设置权限
    print_info "正在同步 SSH 配置..."
    
    # 添加 GitHub 到 known_hosts 避免首次连接提示
    ssh-keyscan -H github.com >> "$HOME/.ssh/known_hosts" 2>/dev/null
    
    if retry_cmd git pull origin main --allow-unrelated-histories 2>/dev/null || \
       retry_cmd git pull origin master --allow-unrelated-histories 2>/dev/null; then
        print_info "SSH 配置拉取成功"
    else
        print_warn "SSH 配置拉取失败（可能是空仓库或首次使用），继续执行..."
    fi

    # 设置权限
    chmod 700 "$HOME/.ssh"
    chmod 600 "$HOME/.ssh"/* 2>/dev/null
    
    print_info "SSH配置已同步"
fi

# ============================================
# Zsh 配置部分
# ============================================

# 检查并安装 zsh
if ! command -v zsh &> /dev/null; then
    print_warn "zsh 未安装，正在安装..."
    if [[ "$OS_TYPE" == "Linux" ]]; then
        if command -v apt &> /dev/null; then
            sudo apt update && sudo apt install -y zsh
        elif command -v yum &> /dev/null; then
            sudo yum install -y zsh
        elif command -v dnf &> /dev/null; then
            sudo dnf install -y zsh
        elif command -v pacman &> /dev/null; then
            sudo pacman -S --noconfirm zsh
        fi
    elif [[ "$OS_TYPE" == "macOS" ]]; then
        brew install zsh
    elif [[ "$OS_TYPE" == "Windows" ]]; then
        print_error "请手动安装 zsh 或使用 WSL 环境"
        exit 1
    fi
else
    print_info "zsh 已安装"
fi

# 设置 zsh 为默认 shell
ZSH_PATH=$(which zsh)
if [[ "$SHELL" != "$ZSH_PATH" ]]; then
    print_info "设置 zsh 为默认 shell..."
    if ! grep -q "$ZSH_PATH" /etc/shells; then
        echo "$ZSH_PATH" | sudo tee -a /etc/shells > /dev/null
    fi
    chsh -s "$ZSH_PATH"
    print_info "默认 shell 已设置为 zsh，请重新登录以生效"
else
    print_info "zsh 已是默认 shell"
fi

# 检查并安装 oh-my-zsh
if [ ! -d "$HOME/.oh-my-zsh" ]; then
    print_info "oh-my-zsh 未安装，正在安装..."
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
else
    print_info "oh-my-zsh 已安装"
fi

# 定义插件路径
ZSH_CUSTOM="$HOME/.oh-my-zsh/custom"
AUTOSUGGESTIONS_PATH="$ZSH_CUSTOM/plugins/zsh-autosuggestions"
SYNTAX_HIGHLIGHTING_PATH="$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"

# 检查并安装 zsh-autosuggestions 插件
if [ ! -d "$AUTOSUGGESTIONS_PATH" ]; then
    print_info "zsh-autosuggestions 未安装，正在安装..."
    if ! retry_cmd git clone https://github.com/zsh-users/zsh-autosuggestions "$AUTOSUGGESTIONS_PATH"; then
        print_warn "zsh-autosuggestions 安装失败，将跳过该插件"
    fi
else
    print_info "zsh-autosuggestions 已安装"
fi

# 检查并安装 zsh-syntax-highlighting 插件
if [ ! -d "$SYNTAX_HIGHLIGHTING_PATH" ]; then
    print_info "zsh-syntax-highlighting 未安装，正在安装..."
    if ! retry_cmd git clone https://github.com/zsh-users/zsh-syntax-highlighting.git "$SYNTAX_HIGHLIGHTING_PATH"; then
        print_warn "zsh-syntax-highlighting 安装失败，将跳过该插件"
    fi
else
    print_info "zsh-syntax-highlighting 已安装"
fi

# 检查并安装 fzf
if ! command -v fzf &> /dev/null; then
    print_info "fzf 未安装，正在安装..."
    if retry_cmd git clone --depth 1 https://github.com/junegunn/fzf.git "$HOME/.fzf"; then
        if [ -x "$HOME/.fzf/install" ]; then
            "$HOME/.fzf/install" --all
        else
            print_warn "fzf 仓库克隆成功，但未找到 install 脚本"
        fi
    else
        print_warn "fzf 克隆失败，跳过 fzf 安装（后续可以手动安装）"
    fi
else
    print_info "fzf 已安装"
fi

# 备份并替换 .zshrc 文件
timestamp=$(date +%Y%m%d%H%M%S)
ZSHRC="$HOME/.zshrc"
ZSHRC_BAK="$HOME/.zshrc.bak.$timestamp"

if [ -f "$ZSHRC" ]; then
    print_warn "检测到现有的 .zshrc 文件。"
    echo -n "是否需要备份当前的 .zshrc 文件？(Y/n): "
    read -r backup_choice

    if [[ "$backup_choice" == "n" || "$backup_choice" == "N" ]]; then
        print_info "不备份，将直接覆盖 .zshrc 文件。"
    else
        mv "$ZSHRC" "$ZSHRC_BAK"
        print_info "已备份原来的 .zshrc 为 $ZSHRC_BAK"
    fi
else
    print_info "未发现原来的 .zshrc 文件，无需备份"
fi

# 写入新的 .zshrc 文件内容（使用检测到的 locale）
cat << EOF > "$ZSHRC"
export SHELL=/bin/zsh
export ZSH="\$HOME/.oh-my-zsh"
export LANG=$SELECTED_LOCALE
export LC_ALL=$SELECTED_LOCALE
export FZF_DEFAULT_COMMAND='rg --files --hidden --follow --glob "!.git/*"'
export FZF_CTRL_R_OPTS="--preview 'echo {}'"

ZSH_THEME="robbyrussell"

plugins=(
    git
    zsh-autosuggestions
    zsh-syntax-highlighting
    fzf
)

source \$ZSH/oh-my-zsh.sh
source \$ZSH_CUSTOM/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
source \$ZSH_CUSTOM/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

# 自定义 PROMPT
function prompt_setup() {
    # === ① 检测 conda 虚拟环境 ===
    local conda_part=""
    if [[ -n "\$CONDA_DEFAULT_ENV" ]]; then
        conda_part="%F{cyan}(\$CONDA_DEFAULT_ENV)%f "
    fi

    # === ② 主机名颜色（判断是否 SSH）===
    local hostname_color
    if [[ -n "\$SSH_CONNECTION" || -n "\$SSH_CLIENT" || -n "\$SSH_TTY" ]]; then
        hostname_color="%F{green}%m%f:"  # 远程 - 绿色
    else
        hostname_color="%F{yellow}%m%f:"  # 本机 - 黄色
    fi

    # === ③ 路径显示（保留原格式）===
    local path_display=" %F{cyan}\\\$(basename \\\$(dirname \\\$PWD))/%f%F{cyan}\\\$(basename \\\$PWD)/%f "

    # === ④ 拼接最终 PROMPT ===
    PROMPT="\${conda_part}\${hostname_color}\${path_display}"
}

# 设置 precmd hook 以在每次命令前更新 prompt
autoload -Uz add-zsh-hook
add-zsh-hook precmd prompt_setup

setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_SAVE_NO_DUPS
setopt HIST_FIND_NO_DUPS
setopt SHARE_HISTORY

alias ll='ls -la'
alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'

HISTFILE=\$HOME/.zsh_history
HISTSIZE=10000
SAVEHIST=10000
autoload -Uz compinit && compinit

EOF

print_info "配置完成！"
print_info "请执行以下命令之一以生效设置："
echo -e "  ${YELLOW}source ~/.zshrc${NC}  (在当前会话中生效)"
echo -e "  ${YELLOW}exec zsh${NC}         (重启 zsh)"
echo -e "  或重新登录系统"
