/**
 * Lead Scoring Algorithm — Unit Tests
 *
 * Tests the multi-dimension weighted scoring logic extracted from
 * the n8n workflow node "3-Prepare-Data".
 *
 * Run: node tests/test-scoring.js
 */

// ============================================================
// Scoring function (extracted from workflow for testability)
// ============================================================

function calculateScore(aiData) {
  const WEIGHTS = {
    budget: 0.30,
    urgency: 0.20,
    contact_info: 0.20,
    company: 0.15,
    ai_confidence: 0.15,
  };

  function toNullable(value) {
    if (value === null || value === undefined || value === 'null' || value === '') return null;
    return value;
  }

  const company = toNullable(aiData.company);
  const contact_name = toNullable(aiData.contact_name);
  const email = toNullable(aiData.email);
  const budget = toNullable(aiData.budget);
  const urgency = toNullable(aiData.urgency);
  const confidence = aiData.confidence || {};

  const score_breakdown = {};

  // Budget (0-100)
  let budgetScore = 0;
  if (budget) {
    budgetScore = 60;
    if (budget.includes('万') || budget.includes('$') || budget.includes('美元') || budget.includes('k') || budget.includes('K')) {
      budgetScore = 100;
    }
  }
  score_breakdown.budget = { raw: budgetScore, weight: WEIGHTS.budget, weighted: Math.round(budgetScore * WEIGHTS.budget) };

  // Urgency (0-100)
  let urgencyScore = 0;
  if (urgency) {
    urgencyScore = 50;
    if (urgency.includes('天') || urgency.includes('周') || urgency.includes('紧急') || urgency.includes('尽快') || urgency.includes('立即')) {
      urgencyScore = 100;
    } else if (urgency.includes('月') || urgency.includes('季度')) {
      urgencyScore = 70;
    }
  }
  score_breakdown.urgency = { raw: urgencyScore, weight: WEIGHTS.urgency, weighted: Math.round(urgencyScore * WEIGHTS.urgency) };

  // Contact info (0-100)
  let contactScore = 0;
  if (email) contactScore += 60;
  if (contact_name) contactScore += 40;
  score_breakdown.contact_info = { raw: contactScore, weight: WEIGHTS.contact_info, weighted: Math.round(contactScore * WEIGHTS.contact_info) };

  // Company (0-100)
  let companyScore = company ? 100 : 0;
  score_breakdown.company = { raw: companyScore, weight: WEIGHTS.company, weighted: Math.round(companyScore * WEIGHTS.company) };

  // AI Confidence (0-100)
  const confValues = Object.values(confidence);
  let avgConf = confValues.length > 0 ? confValues.reduce((s, v) => s + (typeof v === 'number' ? v : 0), 0) / confValues.length : 0;
  let confScore = Math.round(avgConf * 100);
  score_breakdown.ai_confidence = { raw: confScore, weight: WEIGHTS.ai_confidence, weighted: Math.round(confScore * WEIGHTS.ai_confidence) };

  // Weighted total
  let score = Object.values(score_breakdown).reduce((sum, dim) => sum + dim.weighted, 0);

  // Validation penalty
  const validation = aiData.validation;
  if (validation && validation.score_penalty) {
    score -= validation.score_penalty;
  }

  score = Math.min(Math.max(Math.round(score), 0), 100);

  return { score, score_breakdown };
}

// ============================================================
// Test runner (no dependencies needed)
// ============================================================

let passed = 0;
let failed = 0;

function assert(condition, testName, details) {
  if (condition) {
    console.log(`  PASS  ${testName}`);
    passed++;
  } else {
    console.log(`  FAIL  ${testName}`);
    if (details) console.log(`         ${details}`);
    failed++;
  }
}

// ============================================================
// Test cases
// ============================================================

console.log('\n=== Lead Scoring Algorithm Tests ===\n');

// --- Test 1: High-quality lead (all fields, high confidence) ---
console.log('Test 1: High-quality lead (all fields present)');
{
  const result = calculateScore({
    company: '星辰科技有限公司',
    contact_name: '张伟',
    email: 'zhangwei@xingchen.com',
    budget: '50万',
    urgency: '下周开始对接',
    confidence: { company: 1.0, contact_name: 1.0, email: 1.0, budget: 0.9, urgency: 0.9 },
  });
  assert(result.score >= 70, 'Score should be ≥ 70 (high-quality)', `Got: ${result.score}`);
  assert(result.score >= 85, 'Score should be ≥ 85 (excellent lead)', `Got: ${result.score}`);
  assert(result.score_breakdown.budget.raw === 100, 'Budget raw score should be 100');
  assert(result.score_breakdown.urgency.raw === 100, 'Urgency raw score should be 100 (周)');
  assert(result.score_breakdown.contact_info.raw === 100, 'Contact score should be 100 (email + name)');
  assert(result.score_breakdown.company.raw === 100, 'Company score should be 100');
}

// --- Test 2: Low-quality lead (minimal info) ---
console.log('\nTest 2: Low-quality lead (almost empty)');
{
  const result = calculateScore({
    company: null,
    contact_name: null,
    email: null,
    budget: null,
    urgency: null,
    confidence: { company: 0.0, contact_name: 0.0, email: 0.0, budget: 0.0, urgency: 0.0 },
  });
  assert(result.score < 70, 'Score should be < 70', `Got: ${result.score}`);
  assert(result.score === 0, 'Score should be 0 (no info at all)', `Got: ${result.score}`);
}

// --- Test 3: Medium lead (some fields, moderate confidence) ---
console.log('\nTest 3: Medium-quality lead (partial info)');
{
  const result = calculateScore({
    company: '某电商公司',
    contact_name: null,
    email: 'info@example.com',
    budget: '有预算但未明确',
    urgency: null,
    confidence: { company: 0.7, contact_name: 0.0, email: 1.0, budget: 0.4, urgency: 0.0 },
  });
  assert(result.score >= 30, 'Score should be ≥ 30', `Got: ${result.score}`);
  assert(result.score < 70, 'Score should be < 70 (not CRM-worthy)', `Got: ${result.score}`);
  assert(result.score_breakdown.contact_info.raw === 60, 'Contact score should be 60 (email only, no name)');
}

// --- Test 4: Boundary — score exactly at threshold ---
console.log('\nTest 4: Budget with dollar sign');
{
  const result = calculateScore({
    company: 'ABC Corp',
    contact_name: 'John',
    email: 'john@abc.com',
    budget: '$50K',
    urgency: '不急，下个季度再说',
    confidence: { company: 0.8, contact_name: 0.8, email: 1.0, budget: 0.7, urgency: 0.6 },
  });
  assert(result.score_breakdown.budget.raw === 100, 'Dollar sign should trigger max budget score');
  assert(result.score_breakdown.urgency.raw === 70, 'Quarter (季度) should be medium urgency');
}

// --- Test 5: Edge case — "null" strings ---
console.log('\nTest 5: "null" string handling');
{
  const result = calculateScore({
    company: 'null',
    contact_name: '',
    email: undefined,
    budget: null,
    urgency: 'null',
    confidence: {},
  });
  assert(result.score === 0, 'All null-like values should produce score 0', `Got: ${result.score}`);
}

// --- Test 6: Validation penalty ---
console.log('\nTest 6: Validation penalty applied');
{
  const result = calculateScore({
    company: '测试公司',
    contact_name: '李明',
    email: 'invalid-email',
    budget: '10万',
    urgency: '紧急',
    confidence: { company: 1.0, contact_name: 1.0, email: 0.3, budget: 0.9, urgency: 1.0 },
    validation: { is_valid: false, score_penalty: 20 },
  });
  const resultNoPenalty = calculateScore({
    company: '测试公司',
    contact_name: '李明',
    email: 'invalid-email',
    budget: '10万',
    urgency: '紧急',
    confidence: { company: 1.0, contact_name: 1.0, email: 0.3, budget: 0.9, urgency: 1.0 },
  });
  assert(result.score === resultNoPenalty.score - 20, 'Penalty should reduce score by 20', `Got: ${result.score} vs ${resultNoPenalty.score}`);
}

// --- Test 7: Score bounds (never below 0, never above 100) ---
console.log('\nTest 7: Score bounds [0, 100]');
{
  const result = calculateScore({
    company: null,
    contact_name: null,
    email: null,
    budget: null,
    urgency: null,
    confidence: {},
    validation: { score_penalty: 999 },
  });
  assert(result.score === 0, 'Score should never go below 0', `Got: ${result.score}`);

  const maxResult = calculateScore({
    company: '顶级公司',
    contact_name: '王总',
    email: 'wang@top.com',
    budget: '100万',
    urgency: '紧急',
    confidence: { company: 1.0, contact_name: 1.0, email: 1.0, budget: 1.0, urgency: 1.0 },
  });
  assert(maxResult.score <= 100, 'Score should never exceed 100', `Got: ${maxResult.score}`);
}

// --- Test 8: Missing confidence object ---
console.log('\nTest 8: Missing confidence gracefully handled');
{
  const result = calculateScore({
    company: '某公司',
    contact_name: null,
    email: 'test@test.com',
    budget: null,
    urgency: null,
  });
  assert(result.score_breakdown.ai_confidence.raw === 0, 'Missing confidence should default to 0');
  assert(typeof result.score === 'number', 'Should still produce a numeric score');
}

// ============================================================
// Summary
// ============================================================

console.log(`\n${'='.repeat(40)}`);
console.log(`Results: ${passed} passed, ${failed} failed, ${passed + failed} total`);
console.log('='.repeat(40));

if (failed > 0) {
  process.exit(1);
}
