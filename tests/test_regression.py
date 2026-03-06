import os
import pytest
import time
import csv
from coppeliasim_zmqremoteapi_client import RemoteAPIClient
from lib.ArmRobot import UniversalRobot

@pytest.fixture(scope="module")
def sim():
    """Connect to CoppeliaSim and wait until ready"""
    client = RemoteAPIClient(host='127.0.0.1', port=23000)
    sim_obj = None

    max_wait = 60
    interval = 1
    elapsed = 0

    print("→ Waiting for CoppeliaSim ZMQ server...")
    
    # First, check if CoppeliaSim is running
    import socket
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    result = sock.connect_ex(('127.0.0.1', 23000))
    if result == 0:
        print("  → Port 23000 is open (CoppeliaSim might be running)")
    else:
        print("  → Port 23000 is closed (CoppeliaSim might not be running)")
    sock.close()

    while elapsed < max_wait:
        try:
            # Try to get the sim module
            sim_obj = client.require('sim')
            # Test simple call to ensure server responds
            version = sim_obj.getInt32Param(sim_obj.intparam_program_version)
            print(f"  → Connected! CoppeliaSim version: {version}")
            break
        except Exception as e:
            print(f"  → Connection attempt failed: {type(e).__name__}: {e}")
            time.sleep(interval)
            elapsed += interval
            print(f"  still waiting... ({elapsed}s/{max_wait}s)")

    if sim_obj is None:
        # Dump debug information
        print("\n=== DEBUG INFORMATION ===")
        print("Checking if coppeliasim.log exists:")
        if os.path.exists('coppeliasim.log'):
            print("coppeliasim.log found, last 20 lines:")
            with open('coppeliasim.log', 'r') as f:
                lines = f.readlines()[-20:]
                for line in lines:
                    print(f"  {line.strip()}")
        else:
            print("coppeliasim.log not found!")
        
        print("\nChecking running processes:")
        os.system("ps aux | grep coppelia")
        
        print("\nChecking network connections:")
        os.system("netstat -tlnp | grep 23000 || echo 'Port 23000 not listening'")
        
        pytest.fail("Cannot connect to 'sim' object via ZMQ API - check debug output above")
    
    print("→ Starting simulation")
    try:
        sim_obj.startSimulation()
        time.sleep(2.0)
    except Exception as e:
        print(f"→ Error starting simulation: {e}")
        pytest.fail(f"Failed to start simulation: {e}")
    
    yield sim_obj
    
    print("→ Stopping simulation")
    try:
        sim_obj.stopSimulation()
        time.sleep(0.5)
    except Exception as e:
        print(f"→ Error stopping simulation: {e}")


@pytest.fixture(scope="module")
def create_test_csv():
    """Create a test CSV file if it doesn't exist"""
    csv_path = 'pallet_positions.csv'
    
    # Check if we're in the right directory
    print(f"→ Current working directory: {os.getcwd()}")
    print(f"→ CSV path: {os.path.abspath(csv_path)}")
    
    if not os.path.exists(csv_path):
        print("→ Creating test CSV file with dummy positions")
        try:
            with open(csv_path, 'w', newline='') as file:
                writer = csv.writer(file)
                # Create 21 dummy positions with proper format [x, y, z, alpha, beta, gamma]
                for i in range(21):
                    # Different heights for different layers
                    if i < 7:
                        z = 50  # first layer
                    elif i < 14:
                        z = 250  # second layer
                    else:
                        z = 450  # third layer
                    
                    writer.writerow([100 + (i % 7) * 50, 200, z, 180, 0, 90])
            print(f"→ Created {csv_path} with 21 positions")
        except Exception as e:
            print(f"→ Error creating CSV: {e}")
            raise
    else:
        print(f"→ CSV file already exists, verifying content...")
        try:
            with open(csv_path, 'r') as file:
                reader = csv.reader(file)
                rows = list(reader)
                print(f"→ CSV contains {len(rows)} rows")
                if len(rows) > 0:
                    print(f"→ First row: {rows[0]}")
        except Exception as e:
            print(f"→ Error reading CSV: {e}")
    
    return csv_path


def test_csv_presence(create_test_csv):
    """Test that CSV file exists"""
    assert os.path.exists('pallet_positions.csv'), "CSV file missing!"
    assert os.path.getsize('pallet_positions.csv') > 0, "CSV file is empty!"


def test_load_positions_format(sim, create_test_csv):
    """Test loading positions from CSV"""
    try:
        from main import LoadPalletPosition
        positions = LoadPalletPosition()
        
        assert len(positions) > 0, "No positions loaded"
        assert len(positions[0]) == 6, f"Expected 6 values per position, got {len(positions[0])}"
        
        print(f"→ Successfully loaded {len(positions)} positions")
        print(f"→ First position: {positions[0]}")
        
        # Verify position values are valid
        for i, pos in enumerate(positions):
            assert len(pos) == 6, f"Position {i} has {len(pos)} values, expected 6"
            for j, val in enumerate(pos):
                assert isinstance(val, (int, float)), f"Position {i}, value {j} is not a number: {val}"
                
    except ImportError as e:
        pytest.fail(f"Failed to import LoadPalletPosition from main: {e}")
    except FileNotFoundError as e:
        pytest.fail(f"CSV file not found: {e}")
    except Exception as e:
        pytest.fail(f"Unexpected error loading positions: {type(e).__name__}: {e}")


def test_robot_and_scene(sim, create_test_csv):
    """Test robot initialization and position reading"""
    try:
        robot = UniversalRobot('UR10')
        pos = robot.ReadPosition()
        
        assert pos is not None, "ReadPosition returned None"
        assert len(pos) == 6, f"Expected 6 joint values, got {len(pos)}"
        
        print(f"→ Robot position: {pos}")
        
        # Verify position values are valid
        for i, val in enumerate(pos):
            assert isinstance(val, (int, float)), f"Joint {i} value is not a number: {val}"
            
    except Exception as e:
        pytest.fail(f"Robot initialization failed: {type(e).__name__}: {e}")


def test_gripper_init(sim, create_test_csv):
    """Test gripper initialization"""
    try:
        robot = UniversalRobot('UR10')
        robot.AttachGripper('vacuum_gripper')
        
        assert robot.gripper is not None, "Gripper is None after attachment"
        
        # Test gripper methods if they exist
        if hasattr(robot.gripper, 'Catch'):
            print("→ Gripper has Catch method")
        else:
            print("→ Warning: Gripper missing Catch method")
            
        if hasattr(robot.gripper, 'Release'):
            print("→ Gripper has Release method")
        else:
            print("→ Warning: Gripper missing Release method")
            
        print("→ Gripper initialized successfully")
        
    except Exception as e:
        pytest.fail(f"Gripper initialization failed: {type(e).__name__}: {e}")


@pytest.fixture(scope="module", autouse=True)
def check_coppelia_log():
    """Check CoppeliaSim log for errors before and after tests"""
    log_file = 'coppeliasim.log'
    
    # Check before tests
    if os.path.exists(log_file):
        print("\n=== CoppeliaSim log before tests ===")
        with open(log_file, 'r') as f:
            lines = f.readlines()[-10:]
            for line in lines:
                if 'error' in line.lower() or 'fail' in line.lower() or 'exception' in line.lower():
                    print(f"⚠️  {line.strip()}")
                else:
                    print(f"   {line.strip()}")
    
    yield
    
    # Check after tests
    if os.path.exists(log_file):
        print("\n=== CoppeliaSim log after tests ===")
        with open(log_file, 'r') as f:
            lines = f.readlines()[-10:]
            for line in lines:
                if 'error' in line.lower() or 'fail' in line.lower() or 'exception' in line.lower():
                    print(f"⚠️  {line.strip()}")
                else:
                    print(f"   {line.strip()}")
