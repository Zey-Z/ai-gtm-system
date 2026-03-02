# Prompt Engineering Design

## Evolution: Zero-Shot → Few-Shot + Confidence

### v1: Basic Zero-Shot (Initial)

```
你是一个销售线索信息提取助手。
请提取以下信息并以 JSON 格式返回：
- company, contact_name, email, budget, urgency
输入文本：{text}
请只返回 JSON。
```

**Problems observed:**
- Inconsistent output format across different input styles
- No way to gauge extraction reliability
- Edge cases (ambiguous text, partial info) produced unreliable results

### v2: Few-Shot + Confidence + Analysis Summary (Current)

Key improvements:

| Feature | Purpose |
|---------|---------|
| Few-shot examples (2) | Anchor the model's output format and behavior |
| Confidence scores (0.0-1.0) | Quantify extraction reliability per field |
| Analysis summary | One-line reasoning note for human review |
| Strict JSON Schema | Prevent structural hallucination |

## Design Decisions

### Why Few-Shot Over Zero-Shot?

Few-shot prompting provides "behavioral anchoring" — the model sees concrete input/output pairs and learns the expected pattern. In testing:

| Approach | Format Consistency | Edge Case Handling |
|----------|-------------------|-------------------|
| Zero-shot | ~80% | Poor — model invents fields or changes format |
| Few-shot (2 examples) | ~98% | Good — follows demonstrated pattern |
| Few-shot (5+ examples) | ~99% | Diminishing returns, higher token cost |

**2 examples is the sweet spot**: one high-quality lead (all fields present) and one low-quality lead (minimal info). This teaches the model both extremes.

### Why Confidence Scores Instead of Binary Present/Absent?

Binary output: `"company": "TechCorp"` or `"company": null`

With confidence: `"company": "TechCorp"`, `confidence.company: 0.7`

The confidence score enables:
1. **Scoring integration** — AI confidence is 15% of the final lead score
2. **Quality gates** — Low-confidence fields can be flagged for human review
3. **Analytics** — Track which fields are consistently low-confidence → improve data sources

### Why Analysis Summary Instead of Full Chain-of-Thought?

Chain-of-thought (CoT) prompting makes the model "think aloud":
```
"thinking": "The text mentions '星辰科技' which is likely a company name.
The person says '我是张伟' so the contact name is probably..."
```

**We chose NOT to use full CoT because:**
1. **Token cost** — CoT output can be 3-5× longer, increasing API cost
2. **Latency** — More tokens = slower response time in a real-time pipeline
3. **Parsing complexity** — CoT text needs additional parsing/filtering
4. **Production practice** — In production AI systems, inference outputs should be compact and structured

Instead, we use `analysis_summary` — a **single sentence** that captures the key reasoning:
```
"analysis_summary": "High-quality lead: company, contact, email, clear budget and urgent timeline"
```

This gives human reviewers enough context without the overhead.

### Why Temperature 0.1?

| Temperature | Behavior | Use Case |
|-------------|----------|----------|
| 0.0 | Fully deterministic | When exact reproducibility is required |
| **0.1** | **Near-deterministic with slight variation** | **Structured extraction (our choice)** |
| 0.7 | Creative, varied | Content generation, brainstorming |
| 1.0+ | Highly random | Creative writing |

We use 0.1 (not 0.0) because:
- Same input should produce essentially the same output (deterministic extraction)
- Slight variation (0.1) prevents the model from getting "stuck" on edge cases
- For information extraction, we want consistency, not creativity

### Prompt Language: Chinese

The prompt is written in Chinese because the target market's lead text is in Chinese. Using the same language as the input:
- Reduces translation overhead for the model
- Improves extraction accuracy for Chinese names, company suffixes (有限公司, 集团), and currency terms (万, 元)
- Few-shot examples demonstrate Chinese-specific patterns

## Output Schema

```json
{
  "company": "string | null",
  "contact_name": "string | null",
  "email": "string | null",
  "budget": "string | null",
  "urgency": "string | null",
  "analysis_summary": "string (always present)",
  "confidence": {
    "company": "number 0.0-1.0",
    "contact_name": "number 0.0-1.0",
    "email": "number 0.0-1.0",
    "budget": "number 0.0-1.0",
    "urgency": "number 0.0-1.0"
  }
}
```

### Confidence Scale

| Range | Meaning | Example |
|-------|---------|---------|
| 1.0 | Explicitly stated in text | "我的邮箱是 a@b.com" → email confidence 1.0 |
| 0.7-0.9 | Reasonably inferred | Text mentions "尽快", model infers high urgency |
| 0.3-0.6 | Ambiguous or incomplete | Company name partially mentioned |
| 0.0 | Not mentioned at all | Field returns null, confidence 0.0 |

## Downstream Integration

The confidence scores flow into the scoring algorithm:

```
AI Confidence Score = average(all field confidences) × 100
Weighted Contribution = AI Confidence Score × 0.15 (15% weight)
```

A lead where the AI is confident about all fields gets +15 bonus points. A lead with low confidence across the board loses those points — even if the extracted text looks correct.

## Future Improvements

| Improvement | Expected Impact |
|-------------|----------------|
| Dynamic few-shot selection (RAG) | Select most relevant examples based on input text |
| Model routing | Simple leads → GPT-3.5, complex → GPT-4 |
| Prompt A/B testing | Compare prompt versions on same inputs |
| Multilingual support | English/Chinese prompt switching based on input language |
| Structured output mode | Use OpenAI's native JSON mode with schema enforcement |
