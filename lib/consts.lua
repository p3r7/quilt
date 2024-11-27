

-- ------------------------------------------------------------------------
-- screen

ROT_FPS = 30 -- NB: there is no point in making it faster than FPS
ENV_FPS = 30

FPS = 15
if norns.version == "update	231108" then
  FPS = 30
end


-- ------------------------------------------------------------------------
-- voices

NB_VOICES = 8


-- ------------------------------------------------------------------------
-- waveshape

NB_WAVES = 4

WAVESHAPES = {"SIN", "SAW", "TRI", "SQR"}


-- ------------------------------------------------------------------------
-- poles

p_pargin = 1
p_radius = 10


-- ------------------------------------------------------------------------
-- env / filter graphs

F_GRAPH_H = 30
ENV_GRAPH_H = 25
ENV_GRAPH_X = 8 + 64
ENV_GRAPH_W = 49
GRAPH_BTM_M = 4
