# 토스페이먼츠 대사·정산 관련 API 요약

출처: https://docs.tosspayments.com/reference (코어 API). 구현 전 최신 문서와 API 버전을 반드시 재확인.

## 공통
- 인증: 시크릿 키 Basic 인증(`시크릿키:` base64). **서버에서만 호출.**
- 조회 API는 최대 60초 소요 가능 → 타임아웃 60초 이상.
- 라이브 환경 과다 요청 시 429. 배치에서 재시도 + 백오프.
- 날짜 포맷: ISO 8601, KST(+09:00).

## 거래 조회 — GET /v1/transactions
결제 한 건의 승인·취소·부분취소가 각각 하나의 거래(Transaction).

Query
| 파라미터 | 필수 | 설명 |
|---|---|---|
| startDate | O | `yyyy-MM-dd'T'HH:mm:ss` (날짜만 주면 00:00:00) |
| endDate | O | 위와 동일. 하루 전체면 `T23:59:59` 명시 |
| startingAfter | | 이 transactionKey 이후부터 (페이징 커서) |
| limit | | 기본 100, 최대 5000 |

- 기준 시각: transactionAt(거래 처리 시점). 당일 거래부터 조회 가능.
- 페이징: 받은 건수 == limit 이면 마지막 transactionKey로 startingAfter 재호출, limit 미만이면 종료.

Transaction 주요 필드
`mId, transactionKey, paymentKey, orderId, method, customerKey, status, transactionAt, currency, amount, receiptUrl, useEscrow`

- 대사 키: **transactionKey** (거래 단위), 묶음 키: paymentKey / orderId
- 취소 거래의 amount 부호·표현은 테스트 데이터로 반드시 확인 후 우리 저장 규칙 확정.

## 정산 조회 — GET /v1/settlements
Query
| 파라미터 | 필수 | 설명 |
|---|---|---|
| startDate | O | `yyyy-MM-dd` |
| endDate | O | `yyyy-MM-dd` |
| dateType | | soldDate(기본, 정산 매출일) / paidOutDate(지급일) |
| page | | 1부터 |
| size | | 기본 100, 최대 5000 |

- 결제 다음 날부터 조회 가능 → 정산 배치는 D+1 이후 실행.

Settlement 주요 필드
`paymentKey, transactionKey, orderId, method, amount, interestFee, fees[], payOutAmount, approvedAt, soldDate, paidOutDate, card{...}, cancel{...}`
- fees[].type: BASE, INSTALLMENT_DISCOUNT, INSTALLMENT, POINT_SAVING, ETC (각 fee, supplyAmount, vat)
- payOutAmount = amount − 수수료

## 결제 단건 조회 (불일치 확인용)
- GET /v1/payments/{paymentKey}
- GET /v1/payments/orders/{orderId}
→ Payment 객체: status(DONE/CANCELED/PARTIAL_CANCELED/ABORTED/EXPIRED…), totalAmount, balanceAmount, cancels[], card{issuerCode, acquirerCode, number(마스킹, 최대 20자), approveNo, installmentPlanMonths, cardType, ownerType, acquireStatus}

불일치 상세 화면에서 "PG 최신 상태 확인" 시 서버가 이 API로 재조회.

## 카드 관련 메모
- card.number는 마스킹 값, 최대 20자. 15자리(AMEX), 14자리(Diners), 최대 19자리(UnionPay 등) 존재 → 길이 고정 가정 금지.
- issuerCode(발급사) / acquirerCode(매입사)는 2자리 코드. 화면 표시는 코드표 매핑.
- acquireStatus(매입 상태): READY / REQUESTED / COMPLETED / CANCEL_REQUESTED / CANCELED → 거래 상세에 표시하면 정산 지연 문의 대응에 유용.

## 웹훅
- 결제 상태 변경 이벤트 수신 → 우리 payment 상태 즉시 동기화(대사 불일치 사전 감소).
- secret 필드로 검증.
