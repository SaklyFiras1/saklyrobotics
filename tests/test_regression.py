import os
import pytest
import time
from coppeliasim_zmqremoteapi_client import RemoteAPIClient
from lib.ArmRobot import UniversalRobot


# -----------------------------
# Fixture: Connect to CoppeliaSim
# -----------------------------
@pytest.fixture(scope="module")
def sim():
    client = RemoteAPIClient(host='localhost', port=23000)
    sim_obj = None
    max_wait = 10  # seconds
    interval = 0.5
    elapsed = 0

    # Retry to ensure 'sim' object is ready
    while elapsed < max_wait:
        try:
            sim_obj = client.require('sim')
            break
        except Exception:
            time.sleep(interval)
            elapsed += interval

    if sim_obj is None:
        pytest.fail("Impossible de se connecter à l'objet 'sim' via ZMQ API")

    print("→ Démarrage de la simulation CoppeliaSim...")
    sim_obj.startSimulation()

    # Wait for simulation to settle
    time.sleep(2.0)

    yield sim_obj

    print("→ Arrêt de la simulation CoppeliaSim...")
    sim_obj.stopSimulation()
    time.sleep(0.5)


# -----------------------------
# Test CSV presence
# -----------------------------
def test_csv_presence():
    csv_path = 'pallet_positions.csv'
    assert os.path.exists(csv_path), f"Fichier CSV manquant: {csv_path}"


# -----------------------------
# Test CSV format
# -----------------------------
def test_load_positions_format(sim):
    from main import LoadPalletPosition
    positions = LoadPalletPosition()
    assert len(positions) > 0, "Aucune position chargée depuis le CSV"
    assert len(positions[0]) == 6, f"Chaque position doit avoir 6 valeurs, trouvé: {len(positions[0])}"


# -----------------------------
# Test robot initial position
# -----------------------------
def test_robot_and_scene(sim):
    robot = UniversalRobot('UR10')
    pos = robot.ReadPosition()
    assert len(pos) == 6, f"La position du robot doit contenir 6 valeurs, trouvé: {len(pos)}"


# -----------------------------
# Test gripper initialization
# -----------------------------
def test_gripper_init(sim):
    robot = UniversalRobot('UR10')
    robot.AttachGripper('vacuum_gripper')
    assert robot.gripper is not None, "Le gripper n'a pas été attaché correctement"
