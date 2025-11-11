# Resolve directory of this script (handles sourcing vs execution and spaces)
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" &>/dev/null && pwd)"
# Repo root assumed one level up
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "Starting local Azure Functions environment from $REPO_ROOT"
echo "Using script directory: $SCRIPT_DIR"

cd "$REPO_ROOT/pipeline"
python -m venv .venv

source ./.venv/bin/activate
pip install -r requirements.txt

func start --build

# func start --build
