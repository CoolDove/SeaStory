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
	{{{ BlackBird, 3 }, { BlackBird, 3 }}, 8},
	{{{ BlackBird, 5 }, { BlackBird, 5 }, {PufferBird, 1}}, 8},

	{{{ PufferBird, 1 }, { PufferBird, 2 }}, 9},
	{{{ BlackBird, 3 }, { PufferBird, 2 }}, 8},
	{{{ BlackBird, 2 }, { BlackBird, 2 }, { PufferBird, 2 }}, 9},
	{{{ BlackBird, 2 }, { BlackBird, 2 }, { PufferBird, 3 }}, 9},
	{{{ BlackBird, 3 }, { BlackBird, 3 }, { PufferBird, 2 }, { PufferBird, 2 }}, 10},

	{{{ BlackBird, 3 }, { BlackBird, 4 }, { PufferBird, 3 }}, 9},
}
