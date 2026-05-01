<?php

declare(strict_types=1);

return [
    /*
    |--------------------------------------------------------------------------
    | Factuurdatum (billing day)
    |--------------------------------------------------------------------------
    | De dag van de maand waarop abonnementen worden gefactureerd (1-28).
    | Gebruik 1 voor de 1e van de maand, 15 voor de 15e, etc.
    | Waarden 29-31 worden niet ondersteund i.v.m. maandlengte.
    */
    'billing_day_of_month' => (int) (env('GYMIES_SUBSCRIPTION_BILLING_DAY', 25)),
];
