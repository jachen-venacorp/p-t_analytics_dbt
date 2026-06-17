{{
    config(
        materialized = 'table'
    )
}}

/*
Grain:
- One row per LinearB team, LinearB user, and period_end.
- If a user belongs to multiple teams in DIM_LINEARB_USER_TEAM, that user’s metric row will appear once per team.

Logic:
- Pulls selected developer productivity, throughput, collaboration, AI adoption, Cursor, Copilot, and GitStream AI review metrics from FCT_LINEARB_MEASUREMENT.
- Joins to DIM_LINEARB_USER to add developer display name and email.
- Joins to DIM_LINEARB_USER_TEAM to add team name.
- AI adoption is shown both separately for Copilot and Cursor, and as combined aggregate totals.
*/

WITH fct_measurements AS (
    SELECT
        internal_user_id,
        period_end,

        contributor_coding_days,
        commit_total_changes,
        commit_involved_repos_count,

        branch_computed_cycle_time_p75,
        pr_new,
        pr_merged,

        pr_reviewed,
        branch_time_to_review_p75,
        pr_review_depth,

        ai_metrics_copilot_total_code_acceptances,
        ai_metrics_cursor_total_code_acceptances,
        ai_metrics_copilot_total_code_lines_accepted,
        ai_metrics_cursor_total_code_lines_accepted,
        ai_metrics_copilot_total_code_lines_suggested,
        ai_metrics_cursor_total_code_tabs_suggested,

        commit_total_count_gitstream_suggestion,

        gitstream_ai_review_pr_coverage,
        gitstream_ai_review_total_count,
        gitstream_ai_review_pr_count,
        gitstream_ai_review_resolved_issues,

        gitstream_ai_review_security_issues_prs_count,
        gitstream_ai_review_security_issues_total_count,
        gitstream_ai_review_bugs_prs_count,
        gitstream_ai_review_bugs_total_count,
        gitstream_ai_review_performance_issues_prs_count,
        gitstream_ai_review_performance_issues_total_count,
        gitstream_ai_review_readability_issues_prs_count,
        gitstream_ai_review_readability_issues_total_count,
        gitstream_ai_review_maintainability_issues_prs_count,
        gitstream_ai_review_maintainability_issues_total_count,
        gitstream_ai_review_scope_issues_prs_count,
        gitstream_ai_review_scope_issues_total_count
    FROM {{ source('product_team_analytics', 'fct_linearb_measurement') }}
),

user_dim AS (
    SELECT
        user_id,
        organization_id,
        display_name,
        email
    FROM {{ source('product_team_analytics', 'dim_linearb_user') }}
),

user_team_dim AS (
    SELECT
        user_id,
        organization_id,
        team_id,
        team_nm
    FROM {{ source('product_team_analytics', 'dim_linearb_user_team') }}
)

SELECT
    t.team_nm AS team_name,
    u.display_name AS user_display_name,
    u.email AS user_email,
    f.period_end,

    u.display_name AS developer,

    f.contributor_coding_days AS active_days,
    f.commit_total_changes AS loc_changes,
    f.commit_involved_repos_count AS repositories,

    f.branch_computed_cycle_time_p75 AS cycle_time,
    f.pr_new AS prs_opened,
    f.pr_merged AS merge_frequency,

    f.pr_reviewed AS prs_reviewed,
    f.branch_time_to_review_p75 AS pr_pickup_time,
    f.pr_review_depth AS review_depth,

    f.ai_metrics_copilot_total_code_acceptances AS copilot_ai_actions,
    f.ai_metrics_copilot_total_code_lines_accepted AS copilot_ai_lines_accepted,
    f.ai_metrics_copilot_total_code_lines_suggested AS copilot_ai_lines_added,

    f.ai_metrics_cursor_total_code_acceptances AS cursor_ai_actions,
    f.ai_metrics_cursor_total_code_lines_accepted AS cursor_ai_lines_accepted,
    f.ai_metrics_cursor_total_code_tabs_suggested AS cursor_ai_lines_added,

    COALESCE(f.ai_metrics_copilot_total_code_acceptances, 0)
      + COALESCE(f.ai_metrics_cursor_total_code_acceptances, 0) AS total_ai_actions,

    COALESCE(f.ai_metrics_copilot_total_code_lines_accepted, 0)
      + COALESCE(f.ai_metrics_cursor_total_code_lines_accepted, 0) AS total_ai_lines_accepted,

    COALESCE(f.ai_metrics_copilot_total_code_lines_suggested, 0)
      + COALESCE(f.ai_metrics_cursor_total_code_tabs_suggested, 0) AS total_ai_lines_added,

    f.commit_total_count_gitstream_suggestion AS gitstream_suggested_commits,

    f.gitstream_ai_review_pr_coverage AS gitstream_ai_review_pr_coverage,
    f.gitstream_ai_review_total_count AS gitstream_ai_review_total_reviews,
    f.gitstream_ai_review_pr_count AS gitstream_ai_review_reviewed_prs,
    f.gitstream_ai_review_resolved_issues AS gitstream_ai_review_resolved_issues,

    f.gitstream_ai_review_security_issues_prs_count AS gitstream_ai_review_prs_with_security_issues,
    f.gitstream_ai_review_security_issues_total_count AS gitstream_ai_review_total_security_issues,

    f.gitstream_ai_review_bugs_prs_count AS gitstream_ai_review_prs_with_bug_issues,
    f.gitstream_ai_review_bugs_total_count AS gitstream_ai_review_total_bug_issues,

    f.gitstream_ai_review_performance_issues_prs_count AS gitstream_ai_review_prs_with_performance_issues,
    f.gitstream_ai_review_performance_issues_total_count AS gitstream_ai_review_total_performance_issues,

    f.gitstream_ai_review_readability_issues_prs_count AS gitstream_ai_review_prs_with_readability_issues,
    f.gitstream_ai_review_readability_issues_total_count AS gitstream_ai_review_total_readability_issues,

    f.gitstream_ai_review_maintainability_issues_prs_count AS gitstream_ai_review_prs_with_maintainability_issues,
    f.gitstream_ai_review_maintainability_issues_total_count AS gitstream_ai_review_total_maintainability_issues,

    f.gitstream_ai_review_scope_issues_prs_count AS gitstream_ai_review_prs_with_scope_issues,
    f.gitstream_ai_review_scope_issues_total_count AS gitstream_ai_review_total_scope_issues

FROM fct_measurements f
LEFT JOIN user_dim u
    ON f.internal_user_id = u.user_id
LEFT JOIN user_team_dim t
    ON u.user_id = t.user_id
   AND u.organization_id = t.organization_id