SET NAMES utf8mb4;

-- 1) Health scores bijwerken op basis van boekingen per trainer/klant.
INSERT INTO trainer_client_health_scores (
  trainer_user_id,
  client_user_id,
  health_score,
  retention_risk,
  no_show_risk,
  churn_alert,
  signals_json,
  updated_at,
  created_at
)
SELECT
  a.trainer_user_id,
  a.client_user_id,
  LEAST(
    100,
    GREATEST(
      0,
      100
      - ROUND(COALESCE(a.no_show_rate, 0) * 40)
      - ROUND(COALESCE(a.cancel_rate, 0) * 25)
      - CASE
          WHEN a.recency_days > 14 THEN LEAST(30, (a.recency_days - 14) * 2)
          ELSE 0
        END
    )
  ) AS health_score,
  CASE
    WHEN (
      LEAST(
        100,
        GREATEST(
          0,
          100
          - ROUND(COALESCE(a.no_show_rate, 0) * 40)
          - ROUND(COALESCE(a.cancel_rate, 0) * 25)
          - CASE
              WHEN a.recency_days > 14 THEN LEAST(30, (a.recency_days - 14) * 2)
              ELSE 0
            END
        )
      ) < 45
      OR a.recency_days > 21
    ) THEN 'high'
    WHEN (
      LEAST(
        100,
        GREATEST(
          0,
          100
          - ROUND(COALESCE(a.no_show_rate, 0) * 40)
          - ROUND(COALESCE(a.cancel_rate, 0) * 25)
          - CASE
              WHEN a.recency_days > 14 THEN LEAST(30, (a.recency_days - 14) * 2)
              ELSE 0
            END
        )
      ) < 70
      OR a.recency_days > 14
    ) THEN 'medium'
    ELSE 'low'
  END AS retention_risk,
  CASE
    WHEN COALESCE(a.no_show_rate, 0) >= 0.25 THEN 'high'
    WHEN COALESCE(a.no_show_rate, 0) >= 0.10 THEN 'medium'
    ELSE 'low'
  END AS no_show_risk,
  CASE
    WHEN (
      LEAST(
        100,
        GREATEST(
          0,
          100
          - ROUND(COALESCE(a.no_show_rate, 0) * 40)
          - ROUND(COALESCE(a.cancel_rate, 0) * 25)
          - CASE
              WHEN a.recency_days > 14 THEN LEAST(30, (a.recency_days - 14) * 2)
              ELSE 0
            END
        )
      ) < 45
      OR (a.attendance_drop = 1)
    ) THEN 1
    ELSE 0
  END AS churn_alert,
  JSON_OBJECT(
    'attendance_rate', ROUND(COALESCE(a.attendance_rate, 0), 4),
    'no_show_rate', ROUND(COALESCE(a.no_show_rate, 0), 4),
    'cancel_rate', ROUND(COALESCE(a.cancel_rate, 0), 4),
    'recency_days', a.recency_days,
    'attendance_drop', a.attendance_drop
  ) AS signals_json,
  NOW(),
  NOW()
FROM (
  SELECT
    b.trainer_user_id,
    b.client_user_id,
    SUM(CASE WHEN b.status IN ('completed', 'confirmed') THEN 1 ELSE 0 END) AS attended_cnt,
    SUM(CASE WHEN b.status = 'no_show' THEN 1 ELSE 0 END) AS no_show_cnt,
    SUM(CASE WHEN b.status = 'cancelled' THEN 1 ELSE 0 END) AS cancelled_cnt,
    SUM(CASE WHEN b.status IN ('completed', 'confirmed', 'no_show', 'cancelled') THEN 1 ELSE 0 END) AS tracked_cnt,
    MAX(CASE WHEN b.status IN ('completed', 'confirmed', 'no_show') THEN b.scheduled_at ELSE NULL END) AS last_session_at,
    COALESCE(
      SUM(CASE WHEN b.status IN ('completed', 'confirmed') THEN 1 ELSE 0 END)
      / NULLIF(SUM(CASE WHEN b.status IN ('completed', 'confirmed', 'no_show', 'cancelled') THEN 1 ELSE 0 END), 0),
      0
    ) AS attendance_rate,
    COALESCE(
      SUM(CASE WHEN b.status = 'no_show' THEN 1 ELSE 0 END)
      / NULLIF(SUM(CASE WHEN b.status IN ('completed', 'confirmed', 'no_show', 'cancelled') THEN 1 ELSE 0 END), 0),
      0
    ) AS no_show_rate,
    COALESCE(
      SUM(CASE WHEN b.status = 'cancelled' THEN 1 ELSE 0 END)
      / NULLIF(SUM(CASE WHEN b.status IN ('completed', 'confirmed', 'no_show', 'cancelled') THEN 1 ELSE 0 END), 0),
      0
    ) AS cancel_rate,
    TIMESTAMPDIFF(
      DAY,
      MAX(CASE WHEN b.status IN ('completed', 'confirmed', 'no_show') THEN b.scheduled_at ELSE NULL END),
      NOW()
    ) AS recency_days,
    CASE
      WHEN (
        SUM(CASE WHEN b.status IN ('completed', 'confirmed') AND b.scheduled_at >= DATE_SUB(NOW(), INTERVAL 30 DAY) THEN 1 ELSE 0 END)
        / NULLIF(SUM(CASE WHEN b.status IN ('completed', 'confirmed', 'no_show', 'cancelled') AND b.scheduled_at >= DATE_SUB(NOW(), INTERVAL 30 DAY) THEN 1 ELSE 0 END), 0)
      ) + 0 < (
        SUM(CASE WHEN b.status IN ('completed', 'confirmed') AND b.scheduled_at >= DATE_SUB(NOW(), INTERVAL 60 DAY) AND b.scheduled_at < DATE_SUB(NOW(), INTERVAL 30 DAY) THEN 1 ELSE 0 END)
        / NULLIF(SUM(CASE WHEN b.status IN ('completed', 'confirmed', 'no_show', 'cancelled') AND b.scheduled_at >= DATE_SUB(NOW(), INTERVAL 60 DAY) AND b.scheduled_at < DATE_SUB(NOW(), INTERVAL 30 DAY) THEN 1 ELSE 0 END), 0)
      ) - 0.20
      THEN 1 ELSE 0
    END AS attendance_drop
  FROM gymies_bookings b
  WHERE b.trainer_user_id IS NOT NULL
    AND b.client_user_id IS NOT NULL
  GROUP BY b.trainer_user_id, b.client_user_id
) a
ON DUPLICATE KEY UPDATE
  health_score = VALUES(health_score),
  retention_risk = VALUES(retention_risk),
  no_show_risk = VALUES(no_show_risk),
  churn_alert = VALUES(churn_alert),
  signals_json = VALUES(signals_json),
  updated_at = VALUES(updated_at);

-- 2) Upsell suggestions genereren (pending) voor risico of high engagement.
INSERT INTO trainer_upsell_suggestions (
  trainer_user_id,
  client_user_id,
  package_id,
  reason,
  confidence,
  status,
  expires_at,
  sent_at,
  created_at,
  updated_at
)
SELECT
  h.trainer_user_id,
  h.client_user_id,
  p.id AS package_id,
  CASE
    WHEN h.retention_risk = 'high' THEN 'reengage_after_dropoff'
    WHEN h.no_show_risk = 'high' THEN 'stabilize_commitment_plan'
    ELSE 'upgrade_high_engagement'
  END AS reason,
  CASE
    WHEN h.retention_risk = 'high' THEN 0.74
    WHEN h.no_show_risk = 'high' THEN 0.66
    ELSE 0.82
  END AS confidence,
  'pending',
  DATE_ADD(NOW(), INTERVAL 14 DAY),
  NULL,
  NOW(),
  NOW()
FROM trainer_client_health_scores h
JOIN gymies_packages p
  ON p.id = (
    SELECT p2.id
    FROM gymies_packages p2
    WHERE p2.trainer_user_id = h.trainer_user_id
    ORDER BY COALESCE(p2.sessions_count, 0) DESC, COALESCE(p2.total_cents, 0) DESC, p2.id DESC
    LIMIT 1
  )
LEFT JOIN trainer_upsell_suggestions ex
  ON ex.trainer_user_id = h.trainer_user_id
 AND ex.client_user_id = h.client_user_id
 AND ex.package_id = p.id
 AND ex.status IN ('pending', 'sent', 'accepted')
 AND (ex.expires_at IS NULL OR ex.expires_at >= NOW())
WHERE ex.id IS NULL
  AND (
    h.retention_risk = 'high'
    OR h.no_show_risk = 'high'
    OR h.health_score >= 78
  );

-- 3) Rebook suggestions genereren (pending) wanneer geen upcoming boeking bestaat.
INSERT INTO trainer_rebook_suggestions (
  trainer_user_id,
  client_user_id,
  booking_id,
  next_slot_at,
  reason,
  confidence,
  status,
  sent_at,
  created_at,
  updated_at
)
SELECT
  h.trainer_user_id,
  h.client_user_id,
  lb.id AS booking_id,
  DATE_ADD(NOW(), INTERVAL 3 DAY) AS next_slot_at,
  CASE
    WHEN h.retention_risk = 'high' THEN 'prevent_churn_rebook'
    WHEN h.no_show_risk = 'high' THEN 'rebook_after_no_show'
    ELSE 'keep_momentum'
  END AS reason,
  CASE
    WHEN h.retention_risk = 'high' THEN 0.78
    WHEN h.no_show_risk = 'high' THEN 0.70
    ELSE 0.60
  END AS confidence,
  'pending',
  NULL,
  NOW(),
  NOW()
FROM trainer_client_health_scores h
JOIN gymies_bookings lb
  ON lb.id = (
    SELECT b2.id
    FROM gymies_bookings b2
    WHERE b2.trainer_user_id = h.trainer_user_id
      AND b2.client_user_id = h.client_user_id
    ORDER BY b2.scheduled_at DESC, b2.id DESC
    LIMIT 1
  )
LEFT JOIN gymies_bookings upcoming
  ON upcoming.trainer_user_id = h.trainer_user_id
 AND upcoming.client_user_id = h.client_user_id
 AND upcoming.scheduled_at > NOW()
 AND upcoming.status IN ('pending', 'confirmed', 'reserved')
LEFT JOIN trainer_rebook_suggestions exr
  ON exr.trainer_user_id = h.trainer_user_id
 AND exr.client_user_id = h.client_user_id
 AND exr.status IN ('pending', 'sent', 'accepted')
WHERE upcoming.id IS NULL
  AND exr.id IS NULL
  AND (
    h.retention_risk IN ('medium', 'high')
    OR h.no_show_risk IN ('medium', 'high')
  );
