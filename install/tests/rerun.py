#!/usr/bin/env python3
import importlib.util
import pathlib
import tomllib
import unittest
import sys
sys.dont_write_bytecode = True

ROOT = pathlib.Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('repair', ROOT / 'lib/repair-config.py')
repair = importlib.util.module_from_spec(spec)
spec.loader.exec_module(repair)


class ConfigRepair(unittest.TestCase):
    def test_corrupted_greeter(self):
        damaged = '''# upstream template
# [session] default,
default = "Umbriel"
[user] default
#
default = "perfect"
[appearance] scheme, password_style, hide_logo
# remaining comments

[appearance.wallpaper]
path = "/keep.png"
'''
        result = repair.repair(damaged, 'greeter', 'perfect')
        data = tomllib.loads(result)
        self.assertEqual(data['user']['default'], 'perfect')
        self.assertEqual(data['session']['default'], 'Umbriel')
        self.assertEqual(data['appearance']['wallpaper']['path'], '/keep.png')
        self.assertEqual(repair.repair(result, 'greeter', 'perfect'), result)

    def test_commented_sections_and_existing_settings(self):
        original = '# [user] default\n# [session] default\n[appearance]\nhide_logo = true\n'
        result = repair.repair(original, 'greeter', 'perfect')
        self.assertTrue(tomllib.loads(result)['appearance']['hide_logo'])
        self.assertEqual(repair.repair(result, 'greeter', 'perfect'), result)

    def test_drm_comments_and_multiline(self):
        for original in ('# [drm]\n# ignored_pci_addresses = ["0000:01:00.0"]\n',
                         '[drm]\nignored_pci_addresses = [\n "0000:02:00.0",\n]\nother = true\n'):
            result = repair.repair(original, 'drm', '0000:01:00.0')
            self.assertIn('0000:01:00.0', tomllib.loads(result)['drm']['ignored_pci_addresses'])
            self.assertEqual(repair.repair(result, 'drm', '0000:01:00.0'), result)
            if 'other' in original:
                self.assertTrue(tomllib.loads(result)['drm']['other'])
                self.assertIn('0000:02:00.0', tomllib.loads(result)['drm']['ignored_pci_addresses'])

    def test_unknown_damage_rejected(self):
        with self.assertRaises(tomllib.TOMLDecodeError):
            repair.repair('[appearance]\nbroken = [', 'greeter', 'perfect')

    def test_keyboard_abnt2(self):
        original = '[input.keyboard]\nlayout = ""\nvariant = ""\n'
        result = repair.repair(original, 'keyboard', 'br', 'abnt2')
        data = tomllib.loads(result)
        self.assertEqual(data['input']['keyboard']['layout'], 'br')
        self.assertEqual(data['input']['keyboard']['variant'], 'abnt2')
        self.assertEqual(repair.repair(result, 'keyboard', 'br', 'abnt2'), result)

    def test_brightness_binds_uncomment(self):
        original = (
            '# "XF86MonBrightnessDown" = { action = "spawn:noctalia msg brightness-down 10", allow_when_locked = true }\n'
            '# "XF86AudioMute" = "spawn:wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"\n'
        )
        result = repair.repair(original, 'brightness-binds', '')
        self.assertIn('"XF86MonBrightnessDown"', result)
        self.assertNotIn('# "XF86MonBrightnessDown"', result)
        self.assertIn('"XF86AudioMute"', result)
        self.assertEqual(repair.repair(result, 'brightness-binds', ''), result)

    def test_caelestia_visual_chrome(self):
        original = '''[appearance]
border_width = 2
corner_radius = 10
[appearance.blur]
enabled = true
passes = 3
radius = 3
noise = 0.02
brightness = 0.9
contrast = 0.9
saturation = 1.1
[appearance.shadow]
enabled = true
softness = 10
offset_x = 2
offset_y = 2
[layout]
mode = "scrolling"
gap = 8
[animation]
enabled = true
duration_ms = 250
[animation.beziers]
[animation.windows_in]
enabled = true
duration_ms = 150
curve = "easeout"
style = "popin"
scale = 0.85
[animation.windows_out]
enabled = true
duration_ms = 150
curve = "easeout"
style = "fade"
[animation.windows_move]
enabled = true
duration_ms = 250
curve = "snappy"
[animation.workspaces]
enabled = true
duration_ms = 250
curve = "easeout"
[animation.border]
enabled = false
duration_ms = 250
[animation.scratchpad]
enabled = false
duration_ms = 250
[animation.layers]
enabled = false
[colors]
accent_primary = "#FF0000FF"
[[window_rule]]
blur = true
blur_optimized = false
[[window_rule]]
match.app_id = "^dev.noctalia.Noctalia$"
default_floating = true
'''
        result = repair.repair(original, 'visual', '')
        data = tomllib.loads(result)
        self.assertEqual(data['appearance']['border_width'], 1)
        self.assertEqual(data['appearance']['corner_radius'], 15)
        self.assertEqual(data['appearance']['blur']['passes'], 2)
        self.assertEqual(data['appearance']['blur']['radius'], 8)
        self.assertAlmostEqual(data['appearance']['blur']['noise'], 0.0117)
        self.assertEqual(data['appearance']['blur']['brightness'], 1.0)
        self.assertAlmostEqual(data['appearance']['blur']['contrast'], 0.8916)
        self.assertEqual(data['appearance']['shadow']['softness'], 12)
        self.assertEqual(data['appearance']['shadow']['offset_x'], 0)
        self.assertEqual(data['layout']['gap'], 5)
        self.assertEqual(data['layout']['mode'], 'scrolling')
        anim = data['animation']
        self.assertEqual(anim['windows_in']['duration_ms'], 500)
        self.assertEqual(anim['windows_in']['curve'], 'emphasizedDecel')
        self.assertEqual(anim['windows_out']['duration_ms'], 300)
        self.assertEqual(anim['windows_out']['curve'], 'emphasizedAccel')
        self.assertEqual(anim['windows_move']['duration_ms'], 600)
        self.assertEqual(anim['workspaces']['duration_ms'], 500)
        self.assertTrue(anim['border']['enabled'])
        self.assertEqual(anim['border']['duration_ms'], 600)
        self.assertTrue(anim['scratchpad']['enabled'])
        self.assertEqual(anim['scratchpad']['duration_ms'], 400)
        self.assertFalse(anim['layers']['enabled'])
        self.assertEqual(anim['beziers']['emphasizedDecel'], [0.05, 0.7, 0.1, 1.0])
        self.assertEqual(anim['beziers']['standard'], [0.2, 0.0, 0.0, 1.0])
        self.assertEqual(data['colors']['accent_primary'], '#FF0000FF')
        catch_all, settings = data['window_rule']
        self.assertEqual(catch_all['opacity'], 0.95)
        self.assertTrue(catch_all['blur'])
        self.assertTrue(catch_all['blur_popups'])
        self.assertFalse(catch_all['blur_optimized'])
        self.assertEqual(settings['match']['app_id'], '^dev.noctalia.Noctalia$')
        self.assertTrue(settings['default_floating'])
        self.assertEqual(repair.repair(result, 'visual', ''), result)

    def test_caelestia_visual_inserts_selectorless_rule(self):
        original = '''[appearance]
corner_radius = 10
[[window_rule]]
match.app_id = "^kitty$"
opacity = 1.0
'''
        result = repair.repair(original, 'visual', '')
        rules = tomllib.loads(result)['window_rule']
        self.assertNotIn('match', rules[0])
        self.assertEqual(rules[0]['opacity'], 0.95)
        self.assertEqual(rules[1]['match']['app_id'], '^kitty$')
        self.assertEqual(rules[1]['opacity'], 1.0)

    def test_pandora_keybinds(self):
        original = '''[input.focus]
follows_mouse = false
[keybinds]
"Mod+Return" = "spawn:kitty"
"Mod+T" = "window-toggle-floating"
"Mod+M" = "window-toggle-maximize-to-edges"
"Mod+Ctrl+F" = "window-toggle-maximize"
"Mod+F" = "window-toggle-fullscreen"
"Mod+O" = { action = "overview-toggle", repeat = false }
"Mod+WheelUp" = "window-focus-left"
"Mod+WheelDown" = "window-focus-right"
"Mod+Space" = "scratchpad-toggle"
"Mod+Shift+Space" = "window-move-to-scratchpad"
"Mod+1" = "workspace-switch:1"
'''
        result = repair.repair(original, 'keybinds', '')
        data = tomllib.loads(result)
        self.assertTrue(data['input']['focus']['follows_mouse'])
        pads = {p['name'] for p in data['scratchpad']}
        self.assertEqual(pads, {'general', 'concord', 'sung', 'whatsapp'})
        kb = data['keybinds']
        self.assertIn('spawn:', kb['Mod+C'])
        self.assertIn('cursor', kb['Mod+C'])
        self.assertIn('pandora-scratch-toggle', kb['Mod+D'])
        self.assertIn('concord concord --', kb['Mod+D'])
        self.assertIn('pandora-scratch-toggle', kb['Mod+G'])
        self.assertIn('sung sung --', kb['Mod+G'])
        self.assertIn('firefox --new-window', kb['Mod+W'])
        self.assertNotIn('browser', kb['Mod+W'])
        self.assertIn('whatsapp com.rtosta.zapzap --', kb['Mod+A'])
        self.assertIn('pandora-terminal', kb['Mod+T'])
        self.assertEqual(kb['Mod+Alt+R'], 'window-toggle-floating')
        self.assertEqual(kb['Mod+Alt+F'], 'window-toggle-maximize-to-edges')
        self.assertEqual(kb['Mod+F'], 'window-toggle-fullscreen')
        self.assertEqual(kb['Mod+Alt+H'], 'window-cycle-height')
        self.assertEqual(kb['Mod+Alt+C'], 'column-center')
        self.assertEqual(kb['Mod+Space'], 'scratchpad-toggle:general')
        self.assertEqual(kb['Mod+Alt+3'], 'window-move-to-workspace:3')
        self.assertEqual(kb['Mod+WheelUp']['action'], 'workspace-previous')
        self.assertEqual(kb['Mod+MouseBack']['action'], 'overview-toggle')
        self.assertEqual(kb['Print'], 'spawn:noctalia msg screenshot-region')
        self.assertEqual(kb['Mod+Print'], 'spawn:noctalia msg screenshot-fullscreen')
        self.assertEqual(kb['Mod+V'], 'spawn:noctalia msg panel-toggle clipboard')
        self.assertEqual(kb['Mod+Period'], 'spawn:noctalia msg panel-toggle launcher /emo')
        self.assertEqual(kb['Mod+Alt+Period'], 'window-consume-right')
        self.assertNotIn('Mod+M', kb)
        self.assertNotIn('Mod+Ctrl+F', kb)
        scratch_rules = [r for r in data['window_rule'] if r.get('default_scratchpad')]
        self.assertEqual({r['default_scratchpad'] for r in scratch_rules}, {'concord', 'sung', 'whatsapp'})
        whatsapp_rule = next(r for r in scratch_rules if r['default_scratchpad'] == 'whatsapp')
        self.assertEqual(whatsapp_rule['match']['app_id'], '^com[.]rtosta[.]zapzap$')
        self.assertTrue(data['animation']['scratchpad']['maximize'])
        for rule in scratch_rules:
            self.assertTrue(rule.get('default_maximize'), rule)
        # Idempotent on parsed config (blank-line layout may normalize once).
        second = repair.repair(result, 'keybinds', '')
        self.assertEqual(tomllib.loads(second), tomllib.loads(result))
        self.assertEqual(repair.repair(second, 'keybinds', ''), second)


if __name__ == '__main__':
    unittest.main()
