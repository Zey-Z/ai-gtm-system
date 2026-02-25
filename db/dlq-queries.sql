-- ============================================================
-- DLQ (Dead Letter Queue) 常用查询工具集
-- 使用方法: docker exec -it ai-gtm-system-postgres-1 psql -U aigtm_user -d aigtm -f /db/dlq-queries.sql
-- ============================================================

-- 查询 1: 查看最近的 5 条 DLQ 记录
\echo '========== 最近的 DLQ 记录 =========='
SELECT
  id,
  run_id,
  error_type,
  failed_step,
  LEFT(error_message, 50) as error_msg,
  status,
  retry_count || '/' || max_retries AS retries,
  TO_CHAR(created_at, 'YYYY-MM-DD HH24:MI:SS') as created
FROM dead_letter_queue
ORDER BY created_at DESC
LIMIT 5;

-- 查询 2: 错误统计（按类型和状态分组）
\echo ''
\echo '========== 错误统计 =========='
SELECT
  error_type,
  status,
  COUNT(*) as count,
  ROUND(AVG(retry_count), 2) as avg_retries
FROM dead_letter_queue
GROUP BY error_type, status
ORDER BY count DESC;

-- 查询 3: 待重试任务
\echo ''
\echo '========== 待重试任务 =========='
SELECT
  id,
  run_id,
  error_type,
  failed_step,
  retry_count || '/' || max_retries AS retries,
  TO_CHAR(next_retry_at, 'YYYY-MM-DD HH24:MI:SS') as next_retry
FROM dead_letter_queue
WHERE status = 'pending'
ORDER BY next_retry_at ASC;

-- 查询 4: 今日错误总览
\echo ''
\echo '========== 今日错误总览 =========='
SELECT
  COUNT(*) as total_errors,
  COUNT(CASE WHEN status = 'pending' THEN 1 END) as pending,
  COUNT(CASE WHEN status = 'failed_permanently' THEN 1 END) as failed,
  COUNT(CASE WHEN status = 'resolved' THEN 1 END) as resolved
FROM dead_letter_queue
WHERE created_at >= CURRENT_DATE;
