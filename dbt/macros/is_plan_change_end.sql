{% macro is_plan_change_end(account_id_col, ended_at_col) %}
    EXISTS (
        SELECT 1
        FROM {{ source('raw', 'subscriptions') }} s2
        WHERE s2.account_id = {{ account_id_col }}
          AND {{ ended_at_col }} IS NOT NULL
          AND s2.started_at  = {{ ended_at_col }}
    )
{% endmacro %}
