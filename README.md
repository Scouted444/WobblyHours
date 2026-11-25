# Wobbly Hours (prototype 2)

A chill, physics-y hangout sandbox: a furnished party house, a pool, goofy toys, and friends.
Explosions exist, but they're one toy among many. Godot 4.3+ (GDScript). Everything is built
in code, so there are no scenes to wire up.

## Run it
1. Install Godot 4.3 or newer: https://godotengine.org
2. Import this folder (open `project.godot`), press F5.
3. To test multiplayer on one PC: `Debug > Customize Run Instances > Enable Multiple Instances (2)`.
   Host in one window, join `127.0.0.1` in the other.

## Controls
| Key | Action |
|---|---|
| WASD / Shift / Space | move / sprint / jump (swim up in water) |
| C | swim down |
| Mouse | look (first person) |
| Left mouse | throw what you carry, or shove whatever is in front of you |
| R | flop (ragdoll). R or Space to get up once you've settled. |
| Tab | spawn menu: toys, weapons (pistol, knife, bat), props (cigarette, game console), food (burger, pizza, soda, beer) |
| 1-8 | quick-spawn crate / beach ball / chair / watermelon / duck / bowling pin / barrel / bomb |
| RMB | pick up the prop you look at into your hand / put it down |
| LMB | use what is in your hand (shoot, stab, swing, eat, drink, smoke...); toys get thrown. Beer = wobbly camera, soda = speed boost |
| G | throw what is in your hand |
| K | character creator |
| Esc / Backspace | free the mouse / leave the party |

## What's new in this version
- **First person** with visible arms, head bob, sprint FOV, landing dip. Others see your full body.
- **Humanoid character** (head, torso, upper/lower arms and legs, hair, eyes, shoes) with a
  procedural walk cycle, arms that raise when you carry something, and head pitch that follows
  where you look.
- **Joint ragdoll**: 10 physics bodies connected by cone-twist joints. You go limp when you
  flop, fall from a height, get shoved, or get bonked by a fast-flying toy. Your ragdoll pose is
  synced to everyone.
- **Movement physics**: acceleration and friction, air control, coyote time and jump buffering,
  swimming with buoyancy, wading slowdown, and carrying heavy things slows you down.
- **Grab and carry**: pick up any toy, carry it, throw it. The server holds it, so everyone sees it.
- **The house**: living room (TV, sofas, bookshelves), kitchen, bedroom with a glowing gaming PC,
  bathroom, and a party room with a colour-changing disco floor, disco ball, DJ booth and speakers.
  Doors and windows, textured floors, ceiling lights.
- **The yard**: swimming pool with a diving board, trampoline, ramp, trees, fence, front lawn.
- **Toys with real buoyancy**: duck, beach ball and crate float, watermelons sink slowly.

## Playing with friends online
This build uses direct connections (port 24680, UDP). It works on LAN, or over Tailscale /
ZeroTier / Radmin VPN with no router setup. A Steam relay with 5-letter room codes is the next
networking step.

## Layout
```
autoload/net.gd                host/join + player list
autoload/input_setup.gd        all key bindings (edit here)
scenes/main.gd                 menu + start/stop world
scenes/world/world.gd          spawners, explosions, water, HUD, starting toys
scenes/world/house.gd          walls, doors/windows, living room, kitchen, bedroom, bathroom
scenes/world/house_full.gd     party room, pool, yard (extends house.gd)
scenes/world/prop.gd           all the toys + carrying + buoyancy
scenes/world/mats.gd           materials and procedural textures
scenes/player/player.gd        first-person controller, grab, shove, sync
scenes/player/player_rig.gd    the humanoid model and walk cycle
scenes/player/player_ragdoll.gd  joint ragdoll
```

## Known rough edges
- Not yet play-tested in the editor. Please report any red error text.
- No sound yet. Characters are fixed per player (customizer comes later).
- Client ragdolls push toys through small network nudges, so heavy pile-ups can look floaty.

## Workshop (characters & maps)

Main menu > "Workshop". Install `.glb` (glTF Binary) files by dragging them onto the window, pasting a direct
link, or from the catalog (`content/catalog.json` ships with a few Khronos sample models; you can also point
it at your own online JSON list: `[{"name","kind":"characters|maps","url","author","license"}]`).

* Characters: pick "Use" and everyone in your party sees your model (it is sent to them automatically). It is scaled
  to 1.8 m tall and plays its walk/idle animation if it has one. When ragdolled you fall as the default dummy.
* Maps: pick "Use" and host. Every mesh becomes solid; put an empty node named `spawn...` in the model to choose
  the spawn point, otherwise players drop in at the middle of the map. Joining players download the map from the host.
* Files live in `user://content/` (Godot: Project > Open User Data Folder).

Free sources: Quaternius, Kenney and Poly Pizza have CC0 models; export/convert to `.glb`. Check each license.
Untested in-engine: report any error you see and it will be fixed.

## Menus, computer, chat

* Start menu: animated logo, Host / Join, Customize, Workshop, Settings (sensitivity, FOV, volume, fullscreen), Quit.
* Esc in game: pause menu (the party keeps running). Backspace no longer leaves; use the pause menu.
* T: chat (shown bottom-left for a few seconds). F near the bedroom computer: Wobbly 95, a 1995 desktop with
  Notepad, Paint, Minesweeper, Snake, Party Chat, Jukebox (everyone near the PC hears it), a recycle bin that holds
  a duck, and FREE_PRIZE.exe. Leave it alone for 25 seconds for the screensaver. Esc powers it off.


## Models (real .glb files)
All furniture, props, items, the pool gear and the character body parts are real glTF models in `models/`.
- Open them in Blender, edit and re-export with the same file name, or drop in your own `.glb`.
- `python3 tools/make_models.py` regenerates all of them (needs only numpy); `tools/preview.py` makes a quick PNG preview.
- Named nodes the game looks for: `Flash` (muzzle flash), `Screen` (console screen), `Flame` (rocket), `Board` (diving board, animates).
- Material names `skin`, `shirt`, `pants`, `shoe`, `sole`, `hair` in `person_*.glb` get re-coloured by the character customizer.
- The beach ball stays code-made because every ball gets its own colour.

## New in this build
- **Physics tamed**: every hit, explosion and throw is speed-capped, your own throws can't knock you over, ragdolls never leave the map.
- **Pick up knocked-out players**: look at a downed player and press F to lift them overhead; F puts them down, LMB throws them, they can wriggle free with Space.
- **RPG** (hard to get): it sits on the house roof. Use the trampoline to get up there. It respawns 75 s after it is taken. Press F near a flying rocket to ride it (steer with your look direction, Space to bail out).
- **Beach balls pop** when shot, stabbed or caught in an explosion.
- Bigger pool, steps moved to the side, bouncy diving board, round trampoline, bench removed, party room doorways cleared.
- **Tykes cozy coupe**: a little red-and-yellow toy car by the yard. Press F next to it to get in, drive with W/S/A/D, hold Shift for the rocket boosters, Space to get out.
- **Explosions** now give a small shove instead of a big launch.
- **New character creator** (K in game, or Customize in the menu): live 3D preview, Male/Female, hair, eyebrows, eyes, mouth, facial hair, glasses, shirt, jacket, bodysuit, pants, belt, shoes, cyber arm, with colour swatches and a custom colour picker. Other players see your character.

## Credits
Sound effects use Kenney's Impact Sounds, RPG Audio, Sci-Fi Sounds, Interface Sounds and UI Audio packs (CC0, www.kenney.nl); see `audio/CREDITS.txt`.
Characters come from **Low Poly Character Maker** by Fernando Lopez, licensed CC-BY 4.0: https://github.com/fernandolv33/lowpoly-chmaker . The models are unmodified (see `models/CREDITS_chmaker.txt`). The editor was rewritten for Godot 4 and this game's multiplayer.

## Sound and music (1.32: real audio)
- Sound effects are now **real recordings**: footsteps, punches, landings, glass, car crashes (crunching metal and rattling bits), knife, cloth rustles, coins and UI clicks come from Kenney's CC0 foley packs. Every sound has several takes and a random one plays each time.
- **Footsteps match the floor**: wood, carpet, grass or concrete/tiles.
- The sounds with no recording (gunshot, splash, pop, burp, eating, drinking, toy horn, boing, explosion layers) are rebuilt at full quality with proper filtering and a bit of room, instead of beeping square waves.
- **A limiter on the master** stops anything getting painfully loud, and the same sound can only stack 6 times at once.
- **1.34 livelier:** a background radio plays happy songs while you hang out (3 new ones: Sunny Afternoon, Backyard Bounce, Cannonball, plus Pool Party and Menu Groove), shuffled and cross-faded, under the Music volume slider. It fades out when the bedroom jukebox (or music you dropped on the window) is playing nearby. Birds chirp from spots all around you and a soft breeze plays outside. The toy coupe's rockets now roar like real boosters: ignition, a continuous engine roar that climbs in pitch with speed, and a sputtering cut-off.
- **1.33 mix pass:** effects are dry (no baked-in echo), have softer treble and rounded-off transients, sit a few dB under the music on a gently compressed bus, pan fully left/right, and get quieter and duller with distance, so you can hear where things are happening without them grabbing your attention.
- The 6 songs are re-produced as proper mixed tracks (electric piano, plucked guitar, warm bass, real-sounding drums, reverb, mastering): Menu Groove (neo-soul), Pool Party (tropical house), Boss Fight (driving rock-synth), Sunset Drive (synthwave), Lazy Sunday (lo-fi), Disco Inferno (disco). They loop seamlessly. Files live in `audio/`; `tools/audio/` has the scripts that build them.
- Your first-person arms and hands are now cut from your creator character (skin, sleeves, jacket, cyber arm).

## Camera, stuck button
- **V** switches between first and third person. In first person you only see your arms; in third person you see your whole character.
- **U** or the pause menu's "I'm stuck! (respawn)" button gets you out of any vehicle, carry or ragdoll and puts you back at the spawn point.
- The toy coupe frees its seat by itself if the driver disappears, and being knocked over throws you out of it.

## Animation
- Walking and running now bend the knees and elbows and bob the hips. Jumping, swimming (body lies flat), carrying a person, holding items and hanging on a rocket each have their own pose, and other players see them.
- Sitting in the toy coupe uses the character maker's own seated animation (the character shrinks to fit the toy car).
- First-person arms are built from simple shapes with a bending elbow and a blocky hand, coloured from your character.
- The coupe follows slopes, so it can drive up ramps.

## If the character still looks stiff
Open the Output panel in Godot after starting the game. If a line starts with `NpcBody: bones not found`, copy it to me: it lists the skeleton's real bone names. Bone names are now matched ignoring dots/underscores/case, so "Thigh.L", "Thigh_L" and "ThighL" all work.

## First-person hands and grips
- Hands now have a palm, four fingers (three joints each) and a thumb (`scenes/player/fp_hand.gd`). The arm bends at the elbow to reach the hand (two-bone IK in `player.gd`), and sleeves end in a proper cuff.
- Every held item has its own grip in `scenes/player/grips.gd`: fist around the pistol grip, knife and bat handles, cans and bottles; thumb-and-finger pinch for the cigarette; the pizza and burger rest on an open palm; the game console is held with both hands, the RPG with both (rear grip and front grip). Crates, balls and other toys are carried in both hands.
- To change how an item is held, edit its entry in `Grips.spec()`: `pos`/`rot` place the item in front of the camera, `at` is the grip point on the item, `G` is where that point sits inside the fist, `curls`/`thumb` are finger bend angles in degrees.
- Cigarettes: left-click lifts the cigarette to your mouth, puffs once it gets there, then lowers it again (about 2 seconds).
- Palms are now a rounded, tapered shape instead of a box.

## Better models
- Every generated model now has surface texture: wood grain, fabric weave, brushed metal, bark, leaves, speckled counter tops, food and rubber (made by `tools/textures.py`, embedded in each .glb and tinted by the material colour). Re-run `python3 tools/make_models.py` after editing.
- More detailed: speaker (real cones, tweeter, port, LED), beanbags (lumpy, seam, zip), garden gnome (face, beard, belt, arms, base), flamingo (S-neck, wings, tail, tucked leg), fence post, ceiling lamp (dome shade), tree and bush (lumpier crowns, root flare), pistol (slide serrations, hammer, chequered grip), knife (sharp edge, fuller), pizza (bubbly cheese, bumpy crust), burger (cheese drips), console (start/select, speaker, shoulder buttons).
- First-person hands: rounded fingers, fingernails and knuckles.
- The pistol is now a classic steel service pistol: long slide with rear grooves, barrel bushing, spur hammer, beaver-tail grip safety, thumb safety, slide stop and chequered brown grips with screws.
- The toy car is a new ride-on buggy: rounded teal tub, white racing stripe, number roundels, open seat, orange roll hoop and spoiler, windscreen, chrome-rimmed headlights, tail lights and chunky treaded wheels with mudguards. It drives and boosts exactly as before.
- The toy car now has a cartoon face: googly eyes that look the way you turn (and glance around when it's parked, and rattle when the boosters fire), eyebrows, rosy cheeks and a big grin.
- You no longer shrink to fit in it: you sit full size with your knees jammed up past the dashboard and splayed out, jiggling, hunched over the tiny steering wheel, head sticking out way above the roll bar. The car squashes down about 15 % under you and bounces on its springs as you drive.
- The toy car has a roof on four posts again (a full-size driver's head pokes up through it). Its colours live in `scenes/world/car_paint.gd`: change `BODY` and `ROOF` there to repaint it (the darker trim follows `BODY`).

## The street and the Corner Shop
- The map now carries on past the front fence: a gate opens onto a pavement, a road with a zebra crossing and street lights, and the CORNER SHOP on the other side (striped awning, OPEN sign, shelves of goods, drinks fridges, a shopkeeper behind the counter).
- Money: everyone starts with $100 and earns $10 every 30 seconds (the server keeps the books, your balance shows top right).
- Walk up to the counter and press F to shop. Small things appear on the counter, big things (car, barrel, crate, chair) are left outside the door. Prices and what's sold are in `PRICES` / `SHOP_SECTIONS` at the bottom of `scenes/world/world.gd`. The Tab spawn menu still works for free sandbox spawning.

## Shopping carts and people
- Shopping carts (3 outside the shop, $25 inside, or Tab > Toys): press F behind one to grab the handle. W/S push, A/D turn on the spot, SHIFT to run with it. Ram into players to bowl them over; run people down.
- People (Tab > People > Person; none appear on their own): random-looking passers-by that stroll around and stand about. Shoot, stab, whack, blow up, throw things at or run them over: they shout, run away from you, and with enough damage keel over (the body lies there for 25 s). Up to 24 at once.
- The shopkeeper now faces the counter.
- Pushing: walk into other players or people to shove them along (sprint to push harder). People grumble ("Watch it!"). LMB shove also staggers people and sends them running.
- Cart rides: one player hops IN the cart (press F at its front or side, or while someone is already pushing it) and sits in the basket, knees up; another grabs the handle from behind and pushes them around. F or Space to climb out. The passenger is never hit by their own cart.
- Blood & dismemberment: off by default. Turn it on in Settings ("Blood & dismemberment"). It only affects the people (NPCs) and only on your computer, so friends can keep it off. With it on, hits spray blood and leave puddles; big hits can knock off an arm, a leg or the head (headshots, knives, bats, explosions, getting run over), which tumble away while the stump spurts. Puddles fade after about 40 s, limbs after 30 s.

## Gloves, body parts, player dismemberment, host tools
- Blood & dismemberment: the HOST's setting decides whether limbs can come off at all (for people and players); your own setting decides whether you see blood. Limbs that come off are real objects everyone sees.
- Rubber gloves (Tab > Props, or $30 at the shop): pick them up and they go on your hands (yellow in first person) until you respawn. With empty hands, LMB at a person (alive or dead) or another player within reach rips off the limb you're looking at and leaves you holding it.
- Body parts (arms, legs, heads) are weapons: LMB swings them (a leg hits hardest), G throws them, RMB puts them down. They come from gore only, not the spawn menu.
- Players can lose limbs too (shots, knives, bats, body parts, explosions, getting run over, gloves). A missing arm disappears from your first-person view; losing your head knocks you down and respawns you after 4 s. Respawning (U, falling off the map) puts you back together.
- Ragdolls: fixed the main cause of the twitching/exploding (the limbs were fighting your own invisible standing capsule), evened out the limb weights, firmer joints, 90 physics ticks per second, and the body model now follows the ragdoll limb-for-limb (left stays left) with the spine and head following too.
- People riding a cart or the toy car no longer trail behind it at speed: everyone sticks riders to their own copy of the vehicle.
- Animations: walking and sprinting now have a proper stride (knees bend on the swing-through), arms swing and bend more when running, the upper body leans into a sprint and rocks side to side while the head stays level; in the air you flail.
- Spawning: 0.6 s cooldown and a limit of 20 things and 8 people per player (a message tells you). Host tools in the pause menu (host only): Clear props, Clear people, Clear blood & body parts, Reset everything, and a "Let guests spawn things" switch.

## Updating to a new version
- Easiest: drag the new `wobbly_hours.zip` I send onto `update.bat` in the game folder. It backs up the current game into `wobbly_hours_backups` (next to the game folder), copies the new files in, and tells you old -> new version. Then open the project in Godot (it re-imports the models).
- Or in the game's main menu: "Update from a new zip..." and pick the zip (works when you run the game from the project / Godot editor). Restart afterwards. The version is shown on the main menu.
- Your settings and saved characters live in your user folder, so updates never touch them. If you exported an .exe, update the project then export again.

## Also new
- No spawn cooldown any more (the per-player limits stay).
- Lost an arm? In first person it's now a see-through glowing ghost arm that still works (others see the arm missing).
- Pool ladders: swim up to one and hold W or Space to climb out.
- Lounge chairs rebuilt: the backrest now rises at the head end on a proper frame, and you can stand/sit on the backrest too.
- 1.21: people and players no longer look like they're coming apart: the character maker's meshes have small gaps at the shoulders, elbows, wrists, knees and ankles that opened up whenever a limb bent. Each joint now has a filler ball, coloured like the sleeve / trouser leg / skin that covers it (it shrinks away with the limb if that limb gets cut off).

## 1.22: weapon wheel and physical melee
- Weapon wheel: hold Q, point at a slot, let go. Picking something up while your hands are full puts what you held into the wheel (7 slots) instead of dropping it. "Empty hands" (top) puts your item away.
- Melee (knife, bat, arms, legs, heads) is now physical: hold LMB to wind up (the weapon pulls back and shakes), let go to swing. The weapon really sweeps an arc across the front of you a moment later; everything it passes through gets smacked ALONG the swing, so props fly sideways and spin, people and players get bowled over the way you swung. Full wind-up hits about 2.6x harder (and swings alternate left/right). A hit gives a little screen kick and a thud.

## 1.23: the launcher (automatic updates for everyone)
The main menu now has a launcher bar: your version, "Check for updates", "Update now" (download + install with a progress bar), "Update from a zip..." (for zips I send you) and "Update link...".

One-time setup (host / whoever shares the game):
1. Make a free GitHub repo, e.g. `yourname/wobbly-hours` (it can be empty).
2. In Godot: Project > Export > Windows Desktop > Export Project to `export/WobblyHours.exe` (the export preset is included).
3. Run `powershell -ExecutionPolicy Bypass -File tools\make_release.ps1 -Repo yourname/wobbly-hours -Notes "what's new"`. It makes `release\WobblyHours_windows.zip`, `release\wobbly_hours_project.zip`, `release\latest.json`, and writes the update link into `update_url.txt`.
4. Export once more (so the link is inside the game) and give friends that `export` folder.
5. On GitHub: Releases > Draft a new release > tag `v1.23` > upload the three files from `release\` > Publish.

Every new version after that: install my zip (update.bat or the launcher's "Update from a zip..."), export, run make_release.ps1, publish a new GitHub release with the three files. Friends just open the game: the launcher says "Update available" and "Update now" downloads it, swaps the files and restarts the game by itself (exported .exe) or updates the project folder (running in Godot).
Players can also paste a link with "Update link..." if you didn't bake it in.

## The separate launcher (WobblyLauncher.exe)
A small program of its own (the `launcher/` folder is its Godot project). Friends run it instead of the game:
- Shows the installed version and checks for a newer one. **INSTALL** / **UPDATE** downloads the new build with a progress bar and unpacks it into its `game\` folder. **PLAY** starts the game and closes the launcher.
- Also: Check for updates, Update from a zip..., Update link... (paste the latest.json link), Open game folder.

Folder layout for players:
```
Wobbly Hours\
  WobblyLauncher.exe
  launcher.json        (the update link)
  game\WobblyHours.exe + WobblyHours.pck + version.txt
```
Making it (once): in Godot, Project Manager > Import > pick `launcher/project.godot` > Export > Windows Desktop (preset included) to `launcher/export/WobblyLauncher.exe`. Then `tools\make_release.ps1` also builds `release\WobblyHours_with_launcher.zip` - the one download new players need (unzip anywhere, run WobblyLauncher.exe). Publish releases on GitHub as described above; from then on the launcher updates everyone by itself.

## 1.24
- Real shopping: in the Corner Shop, look at a shelf and press F to take that item (it's paid for on the spot and lands in your hand; what you held goes in the weapon wheel). Drop or throw things into a shopping cart's basket and they stay in it and ride along while you push (up to 10 things). Pick them back out with RMB; a good whack or an explosion knocks them out.
- Limbs grow back: 15 s after your last lost limb, everything grows back (boing!). People regrow theirs after 20 s if they're still alive.
- Fixed heads tipping backwards: the spine / neck movement for running, ducking in the toy car and ragdolls now bends the model's own posture instead of forcing the neck straight up.
- The joint filler balls were too big and showed as circles on people: they're smaller now and sit inside the arms and legs, only filling the gaps (no more balls on shoulders and ankles).

## Automatic releases (GitHub Actions)
This repository builds itself: whenever `version.txt` changes on `main`, the "Build and release" workflow
(.github/workflows/release.yml) installs Godot 4.3, exports the game and the launcher for Windows, and
publishes a GitHub release `v<version>` with latest.json, WobblyHours_windows.zip, WobblyHours_with_launcher.zip
and wobbly_hours_project.zip. Everyone's launcher then shows UPDATE. No local exporting or uploading needed.
You can also run it by hand: Actions tab > Build and release > Run workflow.
