# scripts\22_admin_revenue_wiring.ps1
# Lancer depuis la racine du projet : C:\Users\awilc\dev_web\montotem-bj
$ErrorActionPreference = 'Stop'
if (-not (Test-Path 'lib')) { throw 'Lancez ce script depuis la racine du projet (dossier contenant lib).' }

function Trouver([string]$Nom) {
  $f = Get-ChildItem -Path 'lib' -Recurse -Filter $Nom -File | Select-Object -First 1
  if (-not $f) { throw "Fichier introuvable : $Nom" }
  return $f.FullName
}

function Patch([string]$Chemin, [string]$Motif, [string]$Remplacement) {
  $brut = [IO.File]::ReadAllText($Chemin)
  $crlf = $brut.Contains("`r`n")
  $txt  = $brut.Replace("`r`n", "`n")
  $re   = [regex]::new($Motif.Replace("`r`n", "`n"), [Text.RegularExpressions.RegexOptions]::Singleline)
  $nom  = Split-Path $Chemin -Leaf
  if (-not $re.IsMatch($txt)) {
    $court = $Motif.Substring(0, [Math]::Min(55, $Motif.Length))
    Write-Host "  [absent] $nom : $court" -ForegroundColor Yellow
    return
  }
  $rempl = $Remplacement.Replace("`r`n", "`n")
  $txt = $re.Replace($txt, [Text.RegularExpressions.MatchEvaluator]{ param($m) $rempl })
  if ($crlf) { $txt = $txt.Replace("`n", "`r`n") }
  [IO.File]::WriteAllText($Chemin, $txt, [Text.UTF8Encoding]::new($false))
  Write-Host "  [ok] $nom" -ForegroundColor Green
}

foreach ($f in @('admin_revenue_service.dart', 'admin_revenue_screen.dart',
                 'provider_earnings_service.dart', 'provider_earnings_screen.dart',
                 'admin_topups_screen.dart')) {
  [void](Trouver $f)
}

# ---------------------------------------------------------------------------
Write-Host "`n1. wallet_model.dart (signe du seuil de blocage)" -ForegroundColor Cyan
$wm = Trouver 'wallet_model.dart'
$p = @'
        case 'wallet_block_threshold_fcfa':\n          seuil = valeur;
'@
$r = @'
        case 'wallet_block_threshold_fcfa':
          seuil = -valeur.abs();
'@
Patch $wm $p $r

# ---------------------------------------------------------------------------
Write-Host "`n2. app_router.dart (routes admin)" -ForegroundColor Cyan
$router = Trouver 'app_router.dart'
$routerTxt = [IO.File]::ReadAllText($router)

if (-not $routerTxt.Contains('admin_topups_screen.dart')) {
  $tf = Get-ChildItem -Path 'lib' -Recurse -Filter 'admin_topups_screen.dart' -File | Select-Object -First 1
  $rel = $tf.FullName.Substring($tf.FullName.IndexOf('\lib\') + 5).Replace('\', '/')
  $p = @'
import '\.\./\.\./features/admin/presentation/admin_settings_screen\.dart';
'@
  $r = "import '../../features/admin/presentation/admin_settings_screen.dart';`nimport '../../$rel';"
  Patch $router $p $r
} else {
  Write-Host '  [ok] import topups deja present' -ForegroundColor Green
}

if (-not $routerTxt.Contains('admin_revenue_screen.dart')) {
  $p = @'
import '\.\./\.\./features/admin/presentation/admin_settings_screen\.dart';
'@
  $r = "import '../../features/admin/presentation/admin_settings_screen.dart';`nimport '../../features/admin/presentation/admin_revenue_screen.dart';"
  Patch $router $p $r
} else {
  Write-Host '  [ok] import revenue deja present' -ForegroundColor Green
}

$settingsRoute = @'
      GoRoute\(\n        path: '/admin/settings',\n        builder: \(_, __\) => const AdminSettingsScreen\(\),\n      \),
'@

if (-not $routerTxt.Contains('AdminTopupsScreen(')) {
  $r = @'
      GoRoute(
        path: '/admin/topups',
        builder: (_, __) => const AdminTopupsScreen(),
      ),
      GoRoute(
        path: '/admin/settings',
        builder: (_, __) => const AdminSettingsScreen(),
      ),
'@
  Patch $router $settingsRoute $r
} else {
  Write-Host '  [ok] route topups deja declaree' -ForegroundColor Green
}

if (-not $routerTxt.Contains('AdminRevenueScreen(')) {
  $r = @'
      GoRoute(
        path: '/admin/revenue',
        builder: (_, __) => const AdminRevenueScreen(),
      ),
      GoRoute(
        path: '/admin/settings',
        builder: (_, __) => const AdminSettingsScreen(),
      ),
'@
  Patch $router $settingsRoute $r
} else {
  Write-Host '  [ok] route revenue deja declaree' -ForegroundColor Green
}

# ---------------------------------------------------------------------------
Write-Host "`n3. admin_dashboard_screen.dart" -ForegroundColor Cyan
$dash = Trouver 'admin_dashboard_screen.dart'

$p = @'
                    _ActionCard\(\n                      icon: Icons\.flag_outlined,
'@
$r = @'
                    _ActionCard(
                      icon: Icons.account_balance_wallet_outlined,
                      titre: 'Recharges de portefeuille',
                      sousTitre: 'Mobile Money \u00e0 v\u00e9rifier',
                      count: s.pendingPayments,
                      color: AppTheme.primaryColor,
                      onTap: () => context.push('/admin/topups'),
                    ),
                    _ActionCard(
                      icon: Icons.flag_outlined,
'@
Patch $dash $p $r

$p = @'
                    QuickTile\(\n                      icon: Icons\.map_outlined,\n                      label: 'Suivi des prestataires',
'@
$r = @'
                    QuickTile(
                      icon: Icons.account_balance_wallet_outlined,
                      label: 'Recharges',
                      color: AppTheme.primaryColor,
                      badge: s.pendingPayments > 0 ? '${s.pendingPayments}' : null,
                      onTap: () => context.push('/admin/topups'),
                    ),
                    QuickTile(
                      icon: Icons.percent_rounded,
                      label: 'Revenus',
                      color: AppTheme.successColor,
                      onTap: () => context.push('/admin/revenue'),
                    ),
                    QuickTile(
                      icon: Icons.map_outlined,
                      label: 'Suivi des prestataires',
'@
Patch $dash $p $r

$p = @'
label: 'Revenus \(30 jours\)',\n\s*value: TravelFee\.fcfa\(s\.revenue30dFcfa\),\n\s*color: AppTheme\.successColor,\n\s*onTap: \(\) => context\.push\('/admin/control\?tab=2'\),
'@
$r = @'
label: 'Commissions (30 jours)',
                      value: TravelFee.fcfa(s.revenue30dFcfa),
                      color: AppTheme.successColor,
                      onTap: () => context.push('/admin/revenue'),
'@
Patch $dash $p $r

$p = @'
'payment_declared' => '/admin/control\?tab=2',
'@
$r = @'
'wallet_topup_submitted' => '/admin/topups',
        'payment_declared' => '/admin/control?tab=2',
'@
Patch $dash $p $r

# ---------------------------------------------------------------------------
Write-Host "`n4. admin_service.dart (statistiques sur les commissions)" -ForegroundColor Cyan
$adm = Trouver 'admin_service.dart'

$p = @'
import '\.\./domain/admin_stats_model\.dart';
'@
$r = @'
import '../domain/admin_stats_model.dart';
import 'admin_revenue_service.dart';
'@
Patch $adm $p $r

$p = @'
return AdminDashboardStats\.fromJson\(Map<String, dynamic>\.from\(data\)\);
'@
$r = @'
final stats = Map<String, dynamic>.from(data);
      await AdminRevenueService().completerStats(stats);
      return AdminDashboardStats.fromJson(stats);
'@
Patch $adm $p $r

# ---------------------------------------------------------------------------
Write-Host "`n5. push_service.dart (notifications de recharge)" -ForegroundColor Cyan
$push = Trouver 'push_service.dart'

$p = @'
'payment_declared' => '/admin/control\?tab=2',
'@
$r = @'
'wallet_topup_submitted' => '/admin/topups',
      'wallet_topup_approved' || 'wallet_topup_rejected' => '/provider/wallet',
      'payment_declared' => '/admin/control?tab=2',
'@
Patch $push $p $r

# ---------------------------------------------------------------------------
Write-Host "`n6. admin_control_tower_screen.dart (onglet Finances)" -ForegroundColor Cyan
$tower = Trouver 'admin_control_tower_screen.dart'

$p = @'
import '\.\./data/admin_control_service\.dart';
'@
$r = @'
import '../data/admin_control_service.dart';
import 'admin_revenue_screen.dart';
'@
Patch $tower $p $r

$p = @'
_FinanceTab\(service: _service\),
'@
Patch $tower $p 'const AdminRevenuePanel(),'

$p = @'
// -+\n// Finances\n// -+\n\nclass _FinanceTab extends StatefulWidget \{.*?(?=// -+\n// Signalements)
'@
Patch $tower $p ''

# ---------------------------------------------------------------------------
Write-Host "`n7. Controles" -ForegroundColor Cyan
Write-Host '  Routes admin declarees :'
Select-String -Path $router -Pattern "path: '/admin/(topups|revenue)'" |
  ForEach-Object { '    {0}: {1}' -f $_.LineNumber, $_.Line.Trim() }
Write-Host '  References a FinanceTab restantes :'
Get-ChildItem -Path 'lib' -Recurse -Filter *.dart |
  Select-String -Pattern '_FinanceTab' |
  ForEach-Object { '    {0}:{1}' -f $_.Path.Replace("$PWD\", ''), $_.LineNumber }

Write-Host "`nTermine. Lancez : flutter pub get ; flutter analyze" -ForegroundColor Cyan