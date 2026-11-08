param([Parameter(Mandatory = $true)][string]$Godot)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$checks = @(
    @('--headless', '--path', $projectRoot, '--editor', '--quit'),
    @('--headless', '--path', $projectRoot, '--script', 'tests/run_tests.gd'),
    @('--headless', '--path', $projectRoot, '--script', 'tests/game_tests.gd'),
    @('--headless', '--path', $projectRoot, '--script', 'tests/regression_tests.gd'),
    @('--headless', '--path', $projectRoot, '--script', 'tests/boundary_tests.gd'),
    @('--headless', '--path', $projectRoot, '--script', 'tests/battle_initiative_tests.gd'),
    @('--headless', '--path', $projectRoot, '--script', 'tests/player_fortune_tests.gd'),
    @('--headless', '--path', $projectRoot, '--script', 'tests/auction_system_tests.gd'),
    @('--headless', '--path', $projectRoot, '--script', 'tests/auction_flow_simulation.gd'),
    @('--headless', '--path', $projectRoot, '--script', 'tests/spell_system_tests.gd', '--', 'spell_trials'),
    @('--headless', '--path', $projectRoot, '--script', 'tests/spell_system_tests.gd', '--', 'spell_trials_stage2'),
    @('--headless', '--path', $projectRoot, '--script', 'tests/spell_system_tests.gd', '--', 'spell_trials_stage3'),
    @('--headless', '--path', $projectRoot, '--script', 'tests/quest_refactor_tests.gd'),
    @('--headless', '--path', $projectRoot, '--script', 'tests/quest_collect_tests.gd'),
    @('--headless', '--path', $projectRoot, '--script', 'tests/quest_board_delivery_tests.gd'),
    @('--headless', '--path', $projectRoot, '--script', 'tests/quest_kill_tests.gd'),
    @('--headless', '--path', $projectRoot, '--script', 'tests/world_time_tests.gd'),
    @('--headless', '--path', $projectRoot, '--script', 'tests/cultivation_growth_tests.gd'),
    @('--headless', '--path', $projectRoot, '--script', 'tests/realm_tier_tests.gd'),
    @('--headless', '--path', $projectRoot, '--script', 'tests/spirit_flow_tests.gd'),
    @('--headless', '--path', $projectRoot, '--script', 'tests/spirit_live_tests.gd'),
    @('--headless', '--path', $projectRoot, '--script', 'tests/time_system_baseline.gd'),
    @('--headless', '--path', $projectRoot, '--quit-after', '3')
)
foreach ($checkArgs in $checks) {
    $result = & $Godot @checkArgs 2>&1
    $exitCode = $LASTEXITCODE
    $result | Write-Output
    if ($exitCode -ne 0 -or ($result | Select-String 'SCRIPT ERROR:|^ERROR:')) {
        throw "Godot check failed: $($checkArgs -join ' ')"
    }
}
Write-Output 'ALL CHECKS PASSED'
