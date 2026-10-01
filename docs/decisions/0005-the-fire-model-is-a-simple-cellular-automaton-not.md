# D5. The fire model is a simple cellular automaton, not real fire physics

Status: accepted (2026-10-01)

A grid of roughly 50 m cells with fuel, slope and wind factors. Each burning cell can
ignite its neighbours with a probability that is biased downwind. Burned cells leave
hotspots that cool exponentially and flare up with a small probability. *Why:* it looks
right, is cheap to compute, and is easy to explain. Realism isn't the point; the app is.
It's also a natural link to FireWatch's own simulation-first approach. The default
scenario is centred near Manavgat, Antalya.
