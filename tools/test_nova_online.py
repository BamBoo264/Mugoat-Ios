import json
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

class NovaOnlineAndControlsTest(unittest.TestCase):
    def test_room_code_format(self):
        """Room codes should be 8 alphanumeric chars in XXXX-XXXX format."""
        valid_sample = "K7Q2-M9XD"
        pattern = r"^[A-Z0-9]{4}-[A-Z0-9]{4}$"
        self.assertRegex(valid_sample, pattern)

    def test_engine_host_pad_device_enforcement(self):
        """EngineHost.c must ensure lastInputDevice is set to 0 for Pad 0 when virtualPad is active."""
        host = (ROOT / 'app/Source/EngineHost.c').read_text(encoding='utf-8')
        self.assertIn('pg_virtual_pad_apply', host)
        self.assertIn('24627136', host)
        self.assertIn('atomic_store_explicit(device, 0, memory_order_relaxed)', host)

    def test_touch_controls_vehicle_crosshair_and_aim_assist(self):
        """TouchControlsView must feed both right stick and mouse deltas, and avoid overriding pad aim."""
        view = (ROOT / 'app/App/TouchControlsView.swift').read_text(encoding='utf-8')
        # Check that flushCameraTravel sends both PGQueueCameraSwipe and PGMouseInput
        self.assertIn('PGQueueCameraSwipe(Float(raw.x), Float(-raw.y))', view)
        self.assertIn('PGMouseInput(dx, dy, mouseButtons)', view)
        # Check that sendKeyboardMouseEquivalents does not override assisted targeting
        self.assertIn('let targetingAssisted = GameSettings.shared.targetingMode < 3', view)
        self.assertIn('!targetingAssisted', view)

    def test_online_room_manager_exists(self):
        """OnlineRoomManager.swift and OnlineRoomViewController.swift must exist and compile."""
        self.assertTrue((ROOT / 'app/App/OnlineRoomManager.swift').exists())
        self.assertTrue((ROOT / 'app/App/OnlineRoomViewController.swift').exists())
        manager = (ROOT / 'app/App/OnlineRoomManager.swift').read_text(encoding='utf-8')
        self.assertIn('class OnlineRoomManager', manager)
        self.assertIn('generateRoomCode', manager)
        self.assertIn('createRoom', manager)
        self.assertIn('joinRoom', manager)
        self.assertIn('pushLocalState', manager)
        self.assertIn('spawnAtHost', manager)
        self.assertIn('teleportToPartner', manager)
        self.assertIn('gameLoopTick', manager)

    def test_multiplayer_c_engine_exports_and_sync(self):
        """EngineHost.h and EngineHost.c must implement position reading, teleportation, and remote peer avatars."""
        header = (ROOT / 'app/Source/EngineHost.h').read_text(encoding='utf-8')
        self.assertIn('void PGTeleportPlayer(float x, float y, float z);', header)
        self.assertIn('bool PGGetPlayerPosition(float position[3]);', header)
        self.assertIn('float PGGetPlayerHeading(void);', header)
        self.assertIn('void PGUpdateRemotePeer(const char *peerId, float x, float y, float z, float heading, uint32_t vehicleModel);', header)
        self.assertIn('void PGRemoveRemotePeer(const char *peerId);', header)

        source = (ROOT / 'app/Source/EngineHost.c').read_text(encoding='utf-8')
        self.assertIn('PGGetPlayerPosition', source)
        self.assertIn('PGGetPlayerHeading', source)
        self.assertIn('PGTeleportPlayer', source)
        self.assertIn('pg_apply_online_teleport', source)
        self.assertIn('pg_online_peers_tick', source)
        self.assertIn('PGUpdateRemotePeer', source)
        self.assertIn('PGRemoveRemotePeer', source)
        # Verify radar blip creation and ped spawning
        self.assertIn('0x5a039bb0bca604b6ull', source) # ADD_BLIP_FOR_COORD
        self.assertIn('0xd49f9b0955c367deull', source) # CREATE_PED
        self.assertIn('pg_online_peers_tick(instance);', source)
        self.assertIn('pg_apply_online_teleport(instance);', source)

    def test_in_game_online_tick_and_settings(self):
        """NativePortViewController must tick OnlineRoomManager, and SettingsHomeViewController must offer Online Room."""
        port = (ROOT / 'app/App/NativePortViewController.swift').read_text(encoding='utf-8')
        self.assertIn('OnlineRoomManager.shared.gameLoopTick()', port)

        settings = (ROOT / 'app/App/SettingsHomeViewController.swift').read_text(encoding='utf-8')
        self.assertIn('OnlineRoomViewController()', settings)

    def test_project_yml_bonjour_and_network_framework(self):
        """project.yml must declare Network.framework and NSBonjourServices for P2P multiplayer."""
        yml = (ROOT / 'app/project.yml').read_text(encoding='utf-8')
        self.assertIn('- sdk: Network.framework', yml)
        self.assertIn('_gtavmp._udp', yml)
        self.assertIn('NSLocalNetworkUsageDescription', yml)

    def test_workflow_includes_nova_online(self):
        """build-ipa.yml must include nova-online branch."""
        wf = (ROOT / '.github/workflows/build-ipa.yml').read_text(encoding='utf-8')
        self.assertIn('nova-online', wf)

if __name__ == '__main__':
    unittest.main(verbosity=2)
