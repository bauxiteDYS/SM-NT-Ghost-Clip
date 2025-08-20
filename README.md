# SM-NT-Ghost-Clip
Sourcemod plugin for Neotokyo that provides the ability to setup rectangular axis-aligned bounding box volumes where the ghost cannot be dropped into

# How it works  
- When a player picks up the Ghost and is touching the ground, that point will continously be updated as the last known valid position for the ghost
- If the the Ghost is then dropped into a Ghost Clip volume, it will teleport to that last valid position
- Upon teleportation the Ghost will have it's motion freezed for 3s, it cannot be moved at all but it can be picked up again, unfortunately there's no notice to players currently of this
- After 3s it will remain frozen in place, meaning it shouldn't fall of a ledge etc by itself, but will now respond to external forces like explosions
- Currently there is a small quirk where bhopping might mean that the last valid position is much further back than expected due to the timing of the recording vs the hop
- More than 32 volumes are not supported

# How to setup zones  

- The first method overrides the second
  
## Method 1 - Place triggers in Hammer
- Make `trigger_multiple` entities with a `targetname` key that starts with and includes `ghost_clip` e.g. `ghost_clip_area1` where you want the Ghost Clip volume to be
- Make sure it is axis-aligned, i.e. not rotated at all in hammer and rectangular in shape, no complex shapes
- Make sure each different trigger solid is a different entity, don't combine seperate solids into one `trigger_multiple`

## Method 2 - Add the areas to the SM config file
- Use hammer or in-game commands like `cl_showpos` to get the min and max coordinates such as:
`"min" "-1321.0 -724.0 -1279.0"` - `"max" "1137.0 1212.0 -1215.0"`
- Have a server operator add it to the SM config file

# How to add the plugin to the server  
- Sourcemod >= 1.11 is recommended and probably required
- Add the plugin and the text file with the Ghost Clip volumes into the appropriate folders on the server
- You must modify the text file with volumes for each map, under a section named after that exact map:
```
"nt_grid_ctg_b2"
{
  "Floor"
  {
    "min" "-1321.0 -724.0 -1279.0"
    "max" "1137.0 1212.0 -1215.0"
  }

  "Truck Bin"
  {
    "min" "-1352.0 1028.0 -723.0"
    "max" "-1224.0 1216.0 -588.0"
  }
}
```
