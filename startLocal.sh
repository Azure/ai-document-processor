cd pipeline
python -m venv .venv

source .venv/bin/activate
pip install -r requirements.txt

func start --build --verbose

# func start --build
