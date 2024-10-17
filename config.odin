package main

EnemyWaveConfig :: struct {
	enemies : []struct {
		type: typeid,
		count: int,
	},
	time : f64,
}
enemy_config :[]EnemyWaveConfig= {
	{{{ BlackBird, 3 }}, 10},
	{{{ BlackBird, 3 }}, 9},
	{{{ BlackBird, 5 }}, 8},
	{{{ BlackBird, 6 }}, 8},
	{{{ BlackBird, 9 }}, 8},

	{{{ BlackBird, 1 }, { PufferBird, 2 }}, 8},
	{{{ BlackBird, 2 }, { PufferBird, 3 }}, 8},
	{{{ BlackBird, 3 }, { PufferBird, 4 }}, 8},
	{{{ BlackBird, 4 }, { PufferBird, 4 }}, 7},
	{{{ BlackBird, 4 }, { PufferBird, 5 }}, 7},
}
