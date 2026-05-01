#!/usr/bin/env php
<?php
/**
 * Patch GymiesOnboardingController om MollieConnectOAuthTrait te gebruiken.
 * Gebruik: php patch_onboarding_mollie.php [pad/naar/GymiesOnboardingController.php]
 *          of: php patch_onboarding_mollie.php [pad/naar/laravel]  (dan wordt controller daar gezocht)
 */

$base = $argv[1] ?? null;
if ($base) {
    if (is_dir($base)) {
        $controllerPath = rtrim($base, '/') . '/app/Http/Controllers/Gymies/GymiesOnboardingController.php';
    } else {
        $controllerPath = $base;
    }
} else {
    $controllerPath = __DIR__ . '/../../app/Http/Controllers/Gymies/GymiesOnboardingController.php';
}
$traitPath = dirname($controllerPath) . '/MollieConnectOAuthTrait.php';

if (!file_exists($controllerPath)) {
    fwrite(STDERR, "Controller niet gevonden: $controllerPath\n");
    exit(1);
}
if (!file_exists($traitPath)) {
    fwrite(STDERR, "MollieConnectOAuthTrait niet gevonden. Sync eerst de backend.\n");
    exit(1);
}

$content = file_get_contents($controllerPath);

if (strpos($content, 'MollieConnectOAuthTrait') !== false) {
    echo "Controller gebruikt al MollieConnectOAuthTrait.\n";
    exit(0);
}

// 1. Voeg "use MollieConnectOAuthTrait;" toe direct na de class-opening
$content = preg_replace(
    '/(class\s+GymiesOnboardingController\s+(?:extends\s+\S+)?\s*\{)/',
    '$1' . "\n    use MollieConnectOAuthTrait;\n",
    $content,
    1
);

// 2. Vervang startMollieConnect - gebruik replaceMethode helper
$content = replaceMethodBody(
    $content,
    'startMollieConnect',
    'return $this->mollieConnectStart($request);'
);

// 3. Vervang mollieConnectCallback
$content = replaceMethodBody(
    $content,
    'mollieConnectCallback',
    'return $this->mollieConnectCallbackHandle($request);'
);

file_put_contents($controllerPath, $content);
echo "GymiesOnboardingController succesvol gepatcht.\n";

function replaceMethodBody(string $content, string $methodName, string $newBody): string
{
    // Zoek: function METHODNAME(...) : ReturnType { ... }
    // Vervang body door $newBody (met correcte indent)
    $pattern = '/(\s*)public\s+function\s+' . preg_quote($methodName, '/') . '\s*\([^)]*\)\s*:\s*\w+\s*\{/s';
    if (!preg_match($pattern, $content, $m)) {
        fwrite(STDERR, "Waarschuwing: Methode $methodName niet gevonden of ander formaat.\n");
        return $content;
    }
    {
        $indent = $m[1];
        $bodyIndent = $indent . '    ';
        $newMethod = $m[0] . "\n" . $bodyIndent . $newBody . "\n" . $indent . '}';
        // Vind de oude methode: van { tot bijpassende }
        $start = strpos($content, $m[0]);
        $openBrace = strpos($content, '{', $start);
        $pos = $openBrace + 1;
        $depth = 1;
        while ($depth > 0 && $pos < strlen($content)) {
            $c = $content[$pos];
            if ($c === '{') $depth++;
            elseif ($c === '}') $depth--;
            $pos++;
        }
        $end = $pos;
        $before = substr($content, 0, $openBrace + 1);
        $after = substr($content, $end);
        $content = $before . "\n" . $bodyIndent . $newBody . "\n" . $indent . '}' . $after;
    }
    return $content;
}
