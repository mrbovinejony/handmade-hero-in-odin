https://yakvi.github.io/handmade-hero-notes/

A collection of my attempts at making this tutorial in odin. I have tried to comment on things that are odin specific so be on the lookout for comments.

Day 4 has some weird pointer arithmetic that I don't understand so I copied this guys code for day 5
https://github.com/acampbellblack/handmade-odin

Day 7 to 9 use DirectSound so I did my best to implement XAudio2 and make a terrible sound, it works but its ugly. 

After I finish the days in the handmade hero notes I'll start working on the videos, progress will definitely be slower though.

skipping all audio stuff until i get the motivation to work through the xaudio2 docs and try to match the HH projects

7-12-26
skipping up until 23, previous tutorials are pretty specific, there are already resources about live editing code in odin. it doesnt look like anything in these tutorials really affects the next ones, but if there is i will come back and do these days too. starting from day 23

7-16-26
skipped some parts between 23 and 27, will add things i skipped if needed for future days, refactoring for actual game code no

7-31-26 
day 34 finally done, used odins mem.arena instead of hh memory stuff, needs no fancy push array or push struct functions

8-3-26 
day 37, instead of using the manual bitmap loader i use odins built in stuff, the relevant procs are in main load_bitmap and draw_bitmap. the bitmap struct is now just an ^Image in game_state, need to include core:image and core:image/bmp
