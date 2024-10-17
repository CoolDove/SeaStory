package main

EnemyWaveConfig :: struct {
	enemies : []EnemyBatch,
	time : f64,
}
EnemyBatch :: struct {
	type: typeid,
	count: int,
}

enemy_config :[]EnemyWaveConfig= {
	{{{ BlackBird, 3 }}, 10},
	{{{ BlackBird, 3 }}, 9},
	{{{ BlackBird, 5 }}, 8},
	{{{ BlackBird, 6 }}, 8},
	{{{ BlackBird, 9 }}, 8},

	{{{ BlackBird, 1 }, { PufferBird, 2 }}, 8},
	{{{ BlackBird, 2 }, { PufferBird, 3 }}, 8},
	{{{ BlackBird, 3 }, { PufferBird, 3 }}, 8},
	{{{ BlackBird, 4 }, { PufferBird, 3 }}, 7},
	{{{ BlackBird, 4 }, { PufferBird, 2 }, { PufferBird, 2 }}, 7},
}
