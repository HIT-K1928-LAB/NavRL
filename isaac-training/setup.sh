#!/bin/bash

# Exit immediately if a command fails
set -Eeuo pipefail
trap 'echo "[ERROR] line $LINENO: $BASH_COMMAND"' ERR
set -x

# Define environment name
ENV_NAME="NavRL"

RECREATE_ENV=1
PYTHON_VERSION="3.10"

# Load Conda environment handling
eval "$(conda shell.bash hook)"

log() {
  echo
  echo "[INFO] $*"
}

conda_env_exists() {
  conda env list | awk '{print $1}' | grep -Fxq "${ENV_NAME}"
}

if conda_env_exists; then
  if [[ "${RECREATE_ENV}" == "1" ]]; then
    log "删除已有 conda 环境: ${ENV_NAME}"
    conda remove -y -n "${ENV_NAME}" --all
    log "重新创建 conda 环境: ${ENV_NAME}"
    conda create -y -n "${ENV_NAME}" "python=${PYTHON_VERSION}"
  else
    log "检测到已有 conda 环境: ${ENV_NAME}，将直接复用"
  fi
else
  log "创建 conda 环境: ${ENV_NAME}"
  conda create -y -n "${ENV_NAME}" "python=${PYTHON_VERSION}"
fi

conda activate "${ENV_NAME}"

# 代理地址
export HTTP_PROXY="http://127.0.0.1:7897"
export HTTPS_PROXY="http://127.0.0.1:7897"
export ALL_PROXY="socks5://127.0.0.1:7897"

# 给 pip 明确指定一次也可以
export PIP_PROXY="http://127.0.0.1:7897"

# Step 1: Setup Orbit
echo "Setting up Orbit..."
# cd ../orbit
cd ./third_party/orbit

# Remove existing symbolic link if it exists
if [ -L "_isaac_sim" ]; then
    echo "Removing existing symbolic link: _isaac_sim"
    rm -rf _isaac_sim
elif [ -e "_isaac_sim" ]; then
    echo "Error: _isaac_sim exists but is not a symlink. Remove it manually."
    exit 1
fi
ln -s ${ISAACSIM_PATH} _isaac_sim
echo "Running orbit.sh setup..."
./orbit.sh --conda $ENV_NAME

python -m pip install -U pip setuptools wheel

python -m pip install \
  "numpy==1.26.4" \
  "pydantic!=1.7,!=1.7.1,!=1.7.2,!=1.7.3,!=1.8,!=1.8.1,<2.0.0,>=1.6.2" \
  "imageio-ffmpeg==0.4.9" \
  "moviepy==1.0.3" \
  "pyyaml" \
  "rospkg" \
  "matplotlib" \
  "tqdm>=4.63.0,<5" \
  "usd-core>=21.11,<24.00" \
  "tomli" \
  "toml" \
  "contourpy>=1.0.1" \
  "fonttools>=4.22.0" \
  "tenacity" \
  "trio" \
  "trio-websocket" \
  "cloudpickle>=1.2.0" \
  "farama-notifications>=0.0.1" \
  "jax-jumpy>=1.0.0" \
  "pyjwt" \
  "triton==2.0.0"

# Step 2: Install dependencies
echo "Installing system dependencies..."
sudo apt update && sudo apt install -y cmake build-essential

# Install Orbit dependencies
echo "Installing Orbit dependencies..."
# ./orbit.sh --install
# ./orbit.sh --extra
python -m pip install -e source/extensions/omni.isaac.contrib_tasks --no-build-isolation
python -m pip install -e source/extensions/omni.isaac.orbit_tasks --no-build-isolation
python -m pip install -e source/extensions/omni.isaac.orbit --no-build-isolation
python -m pip install -e source/extensions/omni.isaac.orbit_assets --no-build-isolation


# Step 3: Navigate to OmniDrones directory
echo "Setting up OmniDrones..."
cd ../OmniDrones
cp -r conda_setup/etc $CONDA_PREFIX

source "${ISAACSIM_PATH}/setup_conda_env.sh"

# Verification
echo "Verifying OmniIsaac Kit installation..."
python -c "from omni.isaac.kit import SimulationApp"

# Step 4: Setup OmniDrones package
echo "Setting up OmniDrones package..."
cd ../OmniDrones
pip install -e .

# Step 5: Install TensorDict and dependencies
echo "Installing TensorDict dependencies..."
python -m pip uninstall -y tensordict
python -m pip install tomli  # If missing 'tomli'
cd ../tensordict
python -m pip install "setuptools<82"
python -m pip install packaging
python -m pip install -e . --no-build-isolation --no-deps


# Step 6: Install TorchRL
echo "Installing TorchRL..."
cd ../rl
python -m pip install -e . --no-build-isolation --no-deps



# Check which torch is being used
python -c "import torch; print(torch.__path__)"

echo "Setup completed successfully!"

