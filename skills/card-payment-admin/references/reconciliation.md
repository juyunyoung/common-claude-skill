# 대사 로직 · 테이블 설계

## 테이블 (최소 구성, DB 무관)

**payment** (우리 결제 마스터)
| 컬럼 | 비고 |
|---|---|
| id | PK |
| store_id | 상점 |
| order_id | 우리 주문번호 = PG orderId, UNIQUE |
| payment_key | PG paymentKey |
| status | 우리 기준 상태 |
| total_amount, balance_amount | 정수 |
| approved_at | |

**payment_tx** (우리 거래 단위: 승인/취소 각각 1행)
| 컬럼 | 비고 |
|---|---|
| id | PK |
| payment_id | FK |
| transaction_key | PG transactionKey, UNIQUE |
| tx_type | APPROVE / CANCEL / PARTIAL_CANCEL |
| amount | 승인 +, 취소 − 로 통일 |
| tx_at | KST |

**pg_transaction** (PG 원본 적재, 수정 금지)
| 컬럼 | 비고 |
|---|---|
| transaction_key | PK |
| payment_key, order_id, method, status, amount, transaction_at | |
| raw_json | 원본 보관 |
| collected_at | 수집 시각 |

**pg_settlement** (PG 정산 원본)
| 컬럼 | 비고 |
|---|---|
| transaction_key | PK |
| payment_key, order_id, amount, fee_total, pay_out_amount, sold_date, paid_out_date | |
| raw_json | |

**recon_result** (대사 결과)
| 컬럼 | 비고 |
|---|---|
| id | PK |
| store_id, recon_date | 대사 기준일 |
| transaction_key, order_id | 어느 한쪽만 있을 수 있음 |
| our_amount, pg_amount, diff_amount | |
| result_code | MATCHED / AMOUNT_MISMATCH / STATUS_MISMATCH / MISSING_IN_OURS / MISSING_IN_PG / TIMING |
| resolve_status | OPEN / CHECKING / RESOLVED / IGNORED |
| resolver, resolved_at, memo | 감사용 |

**recon_daily** (일별 요약, 화면 2용)
`store_id, recon_date, our_approve, our_cancel, our_net, pg_approve, pg_cancel, pg_net, diff, mismatch_count, batch_run_at`

## 일 배치 흐름 (D+1 새벽 권장)

```
1. 대상일 D 의 PG 거래 수집
   GET /v1/transactions?startDate=D T00:00:00&endDate=D T23:59:59&limit=5000
   → startingAfter 페이징 → pg_transaction upsert
2. 우리 payment_tx 에서 tx_at 이 D 인 건 조회
3. transaction_key 기준 FULL OUTER JOIN
   - 양쪽 有, 금액 같음, 상태 일치  → MATCHED
   - 양쪽 有, 금액 다름             → AMOUNT_MISMATCH
   - 양쪽 有, 상태 다름             → STATUS_MISMATCH
   - PG만 有                        → 시각이 경계(예: 23:55~) 이고 우리 D+1에 있으면 TIMING, 아니면 MISSING_IN_OURS
   - 우리만 有                      → 동일하게 TIMING 판별, 아니면 MISSING_IN_PG
   * 우리 쪽 transaction_key 가 비어있는 레거시 건은 order_id + 금액 + 유형으로 보조 매칭
4. recon_result insert (재실행 시 같은 날짜 OPEN 건만 갱신, 처리완료 건은 보존)
5. recon_daily 집계
6. D-1 의 TIMING 건 재검사 → 해소 시 MATCHED
7. 불일치 1건 이상이면 관리자 푸시 알림
```

정산 배치: D+1 이후 `GET /v1/settlements?startDate=D&endDate=D` (soldDate 기준) → pg_settlement 적재. 지급일 화면용으로 paidOutDate 기준 조회도 병행 가능.

## 주의사항
- **멱등성**: 배치 재실행해도 결과 동일해야 함. PG 원본은 upsert, 결과는 OPEN 건만 갱신.
- **부분취소**: 한 paymentKey에 거래 여러 건. 결제 단위가 아닌 거래(transactionKey) 단위로 비교해야 정확.
- **즉시할인/간편결제 포인트**: 우리 금액(상품가) vs PG 금액(실결제) 차이가 구조적으로 날 수 있음 → 비교 금액 기준을 사전에 정의.
- **시간대**: 서버 TZ가 UTC면 날짜 경계가 9시간 밀림. 모든 날짜 계산 KST 고정.
- **망취소**: 승인 응답 타임아웃 후 취소한 건은 PG에 승인+취소 둘 다 남음 → 우리도 둘 다 기록되어야 MATCHED.
- 원본(raw_json) 보관 기간은 전자금융/세무 보관 기준(통상 5년) 검토.

## 관리자 API 예시 (앱이 호출)
```
GET  /admin/summary?date=
GET  /admin/daily?from=&to=
GET  /admin/transactions?from=&to=&type=&recon=&cursor=&size=
GET  /admin/transactions/{paymentKey}
GET  /admin/mismatches?from=&to=&code=&resolve=
PATCH /admin/mismatches/{id}   {resolveStatus, memo}
GET  /admin/settlements?from=&to=&dateType=
POST /admin/exports            {screen, filters} → {exportId}
GET  /admin/exports/{exportId} → {status, downloadUrl}
```
