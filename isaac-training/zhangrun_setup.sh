#!/usr/bin/env bash
set -euo pipefail

# ========= 基础变量 =========
MINICONDA_SH="Miniconda3-latest-Linux-x86_64.sh"
MINICONDA_URL="https://repo.anaconda.com/miniconda/${MINICONDA_SH}"
CONDA_ROOT="/root/miniconda3"
ENV_NAME="navrl"
NAVRL_ROOT="/root/code/NavRL"
ISAAC_SIM_ROOT="/isaac-sim"
ORBIT_ROOT="${NAVRL_ROOT}/isaac-training/third_party/orbit"
OMNIDRONES_ROOT="${NAVRL_ROOT}/isaac-training/third_party/OmniDrones"
TENSORDICT_ROOT="${NAVRL_ROOT}/isaac-training/third_party/tensordict"
RL_ROOT="${NAVRL_ROOT}/isaac-training/third_party/rl"

# ========= 1) 系统依赖 =========
apt-get update
apt-get install -y wget vim git build-essential g++

git config --global --add safe.directory /root/code/NavRL

# ========= 2) 安装 Miniconda =========
cd /root
wget -O "${MINICONDA_SH}" "${MINICONDA_URL}"

bash "${MINICONDA_SH}" -b -p "${CONDA_ROOT}"

# 初始化 conda
eval "$("${CONDA_ROOT}/bin/conda" shell.bash hook)"

# 写入 ~/.bashrc：代理、DISPLAY、conda 初始化
if ! grep -q '### NAVRL_ENV_BEGIN ###' /root/.bashrc; then
cat >> /root/.bashrc <<'EOF'

### NAVRL_ENV_BEGIN ###
# Miniconda
export PATH="/root/miniconda3/bin:$PATH"

# Proxy
export HTTP_PROXY="http://127.0.0.1:7897"
export HTTPS_PROXY="http://127.0.0.1:7897"
export ALL_PROXY="socks5://127.0.0.1:7897"
export PIP_PROXY="http://127.0.0.1:7897"

# Display
export DISPLAY=:3

# Conda init
if [ -f /root/miniconda3/etc/profile.d/conda.sh ]; then
    . /root/miniconda3/etc/profile.d/conda.sh
fi
### NAVRL_ENV_END ###
EOF
fi

source /root/.bashrc

# ========= 3) 配置 conda =========
conda config --add channels https://mirrors.tuna.tsinghua.edu.cn/anaconda/pkgs/main/
conda config --add channels https://mirrors.tuna.tsinghua.edu.cn/anaconda/pkgs/free/
conda config --add channels https://mirrors.tuna.tsinghua.edu.cn/anaconda/pkgs/r/
conda config --set show_channel_urls yes
conda config --set auto_activate_base false

conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main
conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r

# ========= 4) 创建 conda 环境 =========
conda create -y -n "${ENV_NAME}" python=3.10
conda activate "${ENV_NAME}"

# 确保这两个变量为空
unset PYTHONPATH || true
unset PYTHONHOME || true

# ========= 5) 先升级基础打包工具 =========
python -m pip install -U pip==21.2
python -m pip install -U setuptools==75
python -m pip install -U \
  pip \
  "setuptools<82" \
  wheel \
  packaging \
  toml \
  tomli \
  contourpy \
  fonttools \
  ninja

# ========= 6) 仅在 conda 环境中接入 Isaac Sim =========
cd "${ISAAC_SIM_ROOT}"
source setup_conda_env.sh

# ========= 7) 给 orbit 建立 Isaac Sim 软链 =========
cd "${ORBIT_ROOT}"
rm -rf _isaac_sim
ln -sf "${ISAAC_SIM_ROOT}" _isaac_sim

# ========= 8) 以后只把 /isaac-sim 当底座，不在它里面做项目安装 =========
# 继续在 conda 环境中安装，不污染 isaac
python -m pip install \
  "numpy==1.26.4" \
  "pydantic!=1.7,!=1.7.1,!=1.7.2,!=1.7.3,!=1.8,!=1.8.1,<2.0.0,>=1.6.2" \
  "imageio-ffmpeg==0.4.9" \
  "moviepy==1.0.3" \
  pyyaml \
  rospkg \
  matplotlib \
  "tqdm>=4.63.0,<5" \
  "usd-core>=21.11,<24.00" \
  tenacity \
  trio \
  trio-websocket \
  cloudpickle \
  "farama-notifications>=0.0.1" \
  "jax-jumpy>=1.0.0" \
  pyjwt \
  "triton==2.0.0"

# ========= 9) 安装 orbit 扩展 =========
cd "${ORBIT_ROOT}"
python -m pip install -e source/extensions/omni.isaac.contrib_tasks --no-build-isolation
python -m pip install -e source/extensions/omni.isaac.orbit_tasks --no-build-isolation
python -m pip install -e source/extensions/omni.isaac.orbit --no-build-isolation
python -m pip install -e source/extensions/omni.isaac.orbit_assets --no-build-isolation

# ========= 10) 安装 OmniDrones =========
cd "${OMNIDRONES_ROOT}"
python -m pip install -e .

# ========= 11) 安装 tensordict =========
cd "${TENSORDICT_ROOT}"
python -m pip uninstall -y tensordict || true
python -m pip install -e . --no-build-isolation --no-deps

# ========= 12) 安装 rl =========
cd "${RL_ROOT}"
python -m pip install -e . --no-build-isolation --no-deps

# ========= 13) 修改 rl 中第 52 行的颜色映射 =========
# 这里按内容替换，比硬编码“第52行”更稳妥
TARGET_FILE="$(grep -RIl 'trimesh.visual.color.interpolate' "${RL_ROOT}" | head -n 1 || true)"
if [ -n "${TARGET_FILE}" ]; then
    sed -i 's|.*trimesh\.visual\.color\.interpolate.*|colors = trimesh.visual.color.interpolate(heights_normalized, color_map="viridis")|g' "${TARGET_FILE}"
    echo "Patched file: ${TARGET_FILE}"
else
    echo "WARNING: 未找到包含 trimesh.visual.color.interpolate 的文件，请手动修改："
    echo 'colors = trimesh.visual.color.interpolate(heights_normalized, color_map="viridis")'
fi

# ========= 14) 升级 wandb，避免新 API key 长度报错 =========
python -m pip install --upgrade wandb==0.22.3

# ========= 15) 验证版本 =========
echo "===== 不额外 source Isaac 环境时 ====="
cd "${NAVRL_ROOT}"
python -c "import torch, gymnasium, wandb; print('torch', torch.__version__); print('gymnasium', gymnasium.__version__); print('wandb', wandb.__version__)"

echo "===== source Isaac 环境后 ====="
cd "${NAVRL_ROOT}/isaac-training"
source "${ISAAC_SIM_ROOT}/setup_conda_env.sh"
python -c "import torch, gymnasium, wandb; print('torch', torch.__version__); print('gymnasium', gymnasium.__version__); print('wandb', wandb.__version__)"

# ========= 16) 训练入口 =========
cd "${NAVRL_ROOT}/isaac-training"
source "${ISAAC_SIM_ROOT}/setup_conda_env.sh"
python training/scripts/train.py
