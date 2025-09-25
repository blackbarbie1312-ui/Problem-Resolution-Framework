(define-constant ERR-NOT-AUTHORIZED (err u401))
(define-constant ERR-INVALID-INPUT (err u400))
(define-constant ERR-PROBLEM-NOT-FOUND (err u404))
(define-constant ERR-SOLUTION-NOT-FOUND (err u405))
(define-constant ERR-INSUFFICIENT-FUNDS (err u402))
(define-constant ERR-PROBLEM-CLOSED (err u403))
(define-constant ERR-ALREADY-SUBMITTED (err u406))
(define-constant ERR-DEADLINE-PASSED (err u407))
(define-constant ERR-INVALID-STATUS (err u408))
(define-constant ERR-NOT-RESOLVER (err u409))
(define-constant ERR-ALREADY-VOTED (err u410))

(define-constant CONTRACT-OWNER tx-sender)

(define-constant STATUS-ACTIVE u1)
(define-constant STATUS-UNDER-EVALUATION u2)
(define-constant STATUS-RESOLVED u3)
(define-constant STATUS-CANCELLED u4)

(define-constant SOLUTION-PENDING u1)
(define-constant SOLUTION-APPROVED u2)
(define-constant SOLUTION-REJECTED u3)

(define-constant PRIORITY-LOW u1)
(define-constant PRIORITY-MEDIUM u2)
(define-constant PRIORITY-HIGH u3)
(define-constant PRIORITY-CRITICAL u4)

(define-data-var problem-nonce uint u0)
(define-data-var solution-nonce uint u0)
(define-data-var platform-fee uint u2)
(define-data-var min-reward uint u10000)

(define-map problems
  { problem-id: uint }
  {
    creator: principal,
    title: (string-ascii 100),
    description: (string-ascii 1000),
    category: (string-ascii 50),
    priority: uint,
    reward-amount: uint,
    deadline: uint,
    created-at: uint,
    status: uint,
    solution-count: uint,
    winning-solution: (optional uint),
    resolver: (optional principal),
    expertise-required: (list 5 (string-ascii 50))
  }
)

(define-map solutions
  { solution-id: uint }
  {
    problem-id: uint,
    creator: principal,
    title: (string-ascii 100),
    description: (string-ascii 1000),
    implementation-plan: (string-ascii 1000),
    resources-needed: (string-ascii 500),
    timeline-estimate: uint,
    submitted-at: uint,
    status: uint,
    votes: uint,
    effectiveness-score: (optional uint)
  }
)

(define-map solution-votes
  { solution-id: uint, voter: principal }
  {
    voted-at: uint,
    vote-type: bool,
    reasoning: (string-ascii 200)
  }
)

(define-map resolver-profiles
  { resolver: principal }
  {
    problems-solved: uint,
    solutions-submitted: uint,
    success-rate: uint,
    reputation-score: uint,
    expertise-areas: (list 10 (string-ascii 50)),
    total-earned: uint
  }
)

(define-map problem-evaluations
  { problem-id: uint, evaluator: principal }
  {
    evaluated-at: uint,
    complexity-score: uint,
    impact-score: uint,
    urgency-score: uint,
    recommended-approach: (string-ascii 500)
  }
)

(define-map stakeholder-interests
  { problem-id: uint, stakeholder: principal }
  {
    interest-level: uint,
    contribution: uint,
    requirements: (string-ascii 300),
    joined-at: uint
  }
)

(define-public (create-problem
  (title (string-ascii 100))
  (description (string-ascii 1000))
  (category (string-ascii 50))
  (priority uint)
  (reward-amount uint)
  (duration-blocks uint)
  (expertise-required (list 5 (string-ascii 50)))
)
  (let
    (
      (problem-id (+ (var-get problem-nonce) u1))
      (creator tx-sender)
      (deadline (+ stacks-block-height duration-blocks))
    )
    (asserts! (>= reward-amount (var-get min-reward)) ERR-INSUFFICIENT-FUNDS)
    (asserts! (> duration-blocks u0) ERR-INVALID-INPUT)
    (asserts! (> (len title) u0) ERR-INVALID-INPUT)
    (asserts! (> (len description) u10) ERR-INVALID-INPUT)
    (asserts! (and (<= priority u4) (>= priority u1)) ERR-INVALID-INPUT)
    
    (try! (stx-transfer? reward-amount creator (as-contract tx-sender)))
    
    (map-set problems
      {problem-id: problem-id}
      {
        creator: creator,
        title: title,
        description: description,
        category: category,
        priority: priority,
        reward-amount: reward-amount,
        deadline: deadline,
        created-at: stacks-block-height,
        status: STATUS-ACTIVE,
        solution-count: u0,
        winning-solution: none,
        resolver: none,
        expertise-required: expertise-required
      }
    )
    
    (var-set problem-nonce problem-id)
    (ok problem-id)
  )
)

(define-public (submit-solution
  (problem-id uint)
  (title (string-ascii 100))
  (description (string-ascii 1000))
  (implementation-plan (string-ascii 1000))
  (resources-needed (string-ascii 500))
  (timeline-estimate uint)
)
  (let
    (
      (solution-id (+ (var-get solution-nonce) u1))
      (creator tx-sender)
      (problem (unwrap! (map-get? problems {problem-id: problem-id}) ERR-PROBLEM-NOT-FOUND))
    )
    (asserts! (is-eq (get status problem) STATUS-ACTIVE) ERR-PROBLEM-CLOSED)
    (asserts! (< stacks-block-height (get deadline problem)) ERR-DEADLINE-PASSED)
    (asserts! (> (len title) u0) ERR-INVALID-INPUT)
    (asserts! (> (len description) u10) ERR-INVALID-INPUT)
    (asserts! (> timeline-estimate u0) ERR-INVALID-INPUT)
    
    (map-set solutions
      {solution-id: solution-id}
      {
        problem-id: problem-id,
        creator: creator,
        title: title,
        description: description,
        implementation-plan: implementation-plan,
        resources-needed: resources-needed,
        timeline-estimate: timeline-estimate,
        submitted-at: stacks-block-height,
        status: SOLUTION-PENDING,
        votes: u0,
        effectiveness-score: none
      }
    )
    
    (map-set problems
      {problem-id: problem-id}
      (merge problem {solution-count: (+ (get solution-count problem) u1)})
    )
    
    (let
      (
        (profile (default-to
          {problems-solved: u0, solutions-submitted: u0, success-rate: u0, reputation-score: u100, expertise-areas: (list), total-earned: u0}
          (map-get? resolver-profiles {resolver: creator})
        ))
      )
      (map-set resolver-profiles
        {resolver: creator}
        (merge profile {solutions-submitted: (+ (get solutions-submitted profile) u1)})
      )
    )
    
    (var-set solution-nonce solution-id)
    (ok solution-id)
  )
)

(define-public (vote-solution (solution-id uint) (support bool) (reasoning (string-ascii 200)))
  (let
    (
      (voter tx-sender)
      (solution (unwrap! (map-get? solutions {solution-id: solution-id}) ERR-SOLUTION-NOT-FOUND))
      (problem (unwrap! (map-get? problems {problem-id: (get problem-id solution)}) ERR-PROBLEM-NOT-FOUND))
    )
    (asserts! (is-eq (get status problem) STATUS-ACTIVE) ERR-PROBLEM-CLOSED)
    (asserts! (< stacks-block-height (get deadline problem)) ERR-DEADLINE-PASSED)
    (asserts! (is-none (map-get? solution-votes {solution-id: solution-id, voter: voter})) ERR-ALREADY-VOTED)
    
    (map-set solution-votes
      {solution-id: solution-id, voter: voter}
      {
        voted-at: stacks-block-height,
        vote-type: support,
        reasoning: reasoning
      }
    )
    
    (map-set solutions
      {solution-id: solution-id}
      (merge solution {votes: (+ (get votes solution) (if support u1 u0))})
    )
    
    (ok true)
  )
)

(define-public (assign-resolver (problem-id uint) (resolver principal))
  (let
    (
      (problem (unwrap! (map-get? problems {problem-id: problem-id}) ERR-PROBLEM-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender (get creator problem)) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status problem) STATUS-ACTIVE) ERR-INVALID-STATUS)
    (asserts! (is-none (get resolver problem)) ERR-ALREADY-SUBMITTED)
    (asserts! (> (get solution-count problem) u0) ERR-INVALID-INPUT)
    
    (map-set problems
      {problem-id: problem-id}
      (merge problem {
        resolver: (some resolver),
        status: STATUS-UNDER-EVALUATION
      })
    )
    
    (ok true)
  )
)

(define-public (evaluate-solution
  (solution-id uint)
  (effectiveness-score uint)
  (is-winning-solution bool)
)
  (let
    (
      (solution (unwrap! (map-get? solutions {solution-id: solution-id}) ERR-SOLUTION-NOT-FOUND))
      (problem (unwrap! (map-get? problems {problem-id: (get problem-id solution)}) ERR-PROBLEM-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender (unwrap! (get resolver problem) ERR-NOT-RESOLVER)) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status problem) STATUS-UNDER-EVALUATION) ERR-INVALID-STATUS)
    (asserts! (<= effectiveness-score u100) ERR-INVALID-INPUT)
    
    (map-set solutions
      {solution-id: solution-id}
      (merge solution {
        effectiveness-score: (some effectiveness-score),
        status: (if is-winning-solution SOLUTION-APPROVED SOLUTION-PENDING)
      })
    )
    
    (begin
      (if is-winning-solution
        (begin
          (map-set problems
            {problem-id: (get problem-id solution)}
            (merge problem {
              winning-solution: (some solution-id),
              status: STATUS-RESOLVED
            })
          )
          (try! (distribute-reward (get problem-id solution) solution-id))
        )
        false
      )
    )
    
    (ok true)
  )
)

(define-public (add-stakeholder-interest
  (problem-id uint)
  (interest-level uint)
  (contribution uint)
  (requirements (string-ascii 300))
)
  (let
    (
      (stakeholder tx-sender)
      (problem (unwrap! (map-get? problems {problem-id: problem-id}) ERR-PROBLEM-NOT-FOUND))
    )
    (asserts! (not (is-eq (get status problem) STATUS-RESOLVED)) ERR-PROBLEM-CLOSED)
    (asserts! (and (<= interest-level u10) (>= interest-level u1)) ERR-INVALID-INPUT)
    (asserts! (> contribution u0) ERR-INSUFFICIENT-FUNDS)
    
    (try! (stx-transfer? contribution stakeholder (as-contract tx-sender)))
    
    (map-set stakeholder-interests
      {problem-id: problem-id, stakeholder: stakeholder}
      {
        interest-level: interest-level,
        contribution: contribution,
        requirements: requirements,
        joined-at: stacks-block-height
      }
    )
    
    (map-set problems
      {problem-id: problem-id}
      (merge problem {reward-amount: (+ (get reward-amount problem) contribution)})
    )
    
    (ok true)
  )
)

(define-public (submit-problem-evaluation
  (problem-id uint)
  (complexity-score uint)
  (impact-score uint)
  (urgency-score uint)
  (recommended-approach (string-ascii 500))
)
  (let
    (
      (evaluator tx-sender)
      (problem (unwrap! (map-get? problems {problem-id: problem-id}) ERR-PROBLEM-NOT-FOUND))
    )
    (asserts! (is-eq (get status problem) STATUS-ACTIVE) ERR-INVALID-STATUS)
    (asserts! (<= complexity-score u10) ERR-INVALID-INPUT)
    (asserts! (<= impact-score u10) ERR-INVALID-INPUT)
    (asserts! (<= urgency-score u10) ERR-INVALID-INPUT)
    
    (map-set problem-evaluations
      {problem-id: problem-id, evaluator: evaluator}
      {
        evaluated-at: stacks-block-height,
        complexity-score: complexity-score,
        impact-score: impact-score,
        urgency-score: urgency-score,
        recommended-approach: recommended-approach
      }
    )
    
    (ok true)
  )
)

(define-public (update-resolver-expertise
  (resolver principal)
  (expertise-areas (list 10 (string-ascii 50)))
)
  (let
    (
      (profile (default-to
        {problems-solved: u0, solutions-submitted: u0, success-rate: u0, reputation-score: u100, expertise-areas: (list), total-earned: u0}
        (map-get? resolver-profiles {resolver: resolver})
      ))
    )
    (asserts! (is-eq tx-sender resolver) ERR-NOT-AUTHORIZED)
    
    (map-set resolver-profiles
      {resolver: resolver}
      (merge profile {expertise-areas: expertise-areas})
    )
    
    (ok true)
  )
)

(define-public (cancel-problem (problem-id uint))
  (let
    (
      (problem (unwrap! (map-get? problems {problem-id: problem-id}) ERR-PROBLEM-NOT-FOUND))
    )
    (asserts! (or 
      (is-eq tx-sender (get creator problem))
      (is-eq tx-sender CONTRACT-OWNER)
    ) ERR-NOT-AUTHORIZED)
    (asserts! (not (is-eq (get status problem) STATUS-RESOLVED)) ERR-INVALID-STATUS)
    
    (map-set problems
      {problem-id: problem-id}
      (merge problem {status: STATUS-CANCELLED})
    )
    
    (try! (as-contract (stx-transfer? (get reward-amount problem) tx-sender (get creator problem))))
    (ok true)
  )
)

(define-private (distribute-reward (problem-id uint) (winning-solution-id uint))
  (let
    (
      (problem (unwrap! (map-get? problems {problem-id: problem-id}) ERR-PROBLEM-NOT-FOUND))
      (solution (unwrap! (map-get? solutions {solution-id: winning-solution-id}) ERR-SOLUTION-NOT-FOUND))
      (total-reward (get reward-amount problem))
      (platform-fee-amount (/ (* total-reward (var-get platform-fee)) u100))
      (winner-amount (- total-reward platform-fee-amount))
      (winner (get creator solution))
    )
    
    (try! (as-contract (stx-transfer? winner-amount tx-sender winner)))
    
    (let
      (
        (profile (default-to
          {problems-solved: u0, solutions-submitted: u0, success-rate: u0, reputation-score: u100, expertise-areas: (list), total-earned: u0}
          (map-get? resolver-profiles {resolver: winner})
        ))
      )
      (map-set resolver-profiles
        {resolver: winner}
        (merge profile {
          problems-solved: (+ (get problems-solved profile) u1),
          total-earned: (+ (get total-earned profile) winner-amount),
          reputation-score: (+ (get reputation-score profile) u30),
          success-rate: (/ (* (+ (get problems-solved profile) u1) u100) (get solutions-submitted profile))
        })
      )
    )
    
    (ok true)
  )
)

(define-read-only (get-problem (problem-id uint))
  (map-get? problems {problem-id: problem-id})
)

(define-read-only (get-solution (solution-id uint))
  (map-get? solutions {solution-id: solution-id})
)

(define-read-only (get-resolver-profile (resolver principal))
  (map-get? resolver-profiles {resolver: resolver})
)

(define-read-only (get-solution-vote (solution-id uint) (voter principal))
  (map-get? solution-votes {solution-id: solution-id, voter: voter})
)

(define-read-only (get-problem-evaluation (problem-id uint) (evaluator principal))
  (map-get? problem-evaluations {problem-id: problem-id, evaluator: evaluator})
)

(define-read-only (get-stakeholder-interest (problem-id uint) (stakeholder principal))
  (map-get? stakeholder-interests {problem-id: problem-id, stakeholder: stakeholder})
)

(define-read-only (get-platform-stats)
  {
    total-problems: (var-get problem-nonce),
    total-solutions: (var-get solution-nonce),
    platform-fee: (var-get platform-fee),
    min-reward: (var-get min-reward)
  }
)

(define-public (set-platform-fee (new-fee uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (<= new-fee u10) ERR-INVALID-INPUT)
    (var-set platform-fee new-fee)
    (ok true)
  )
)

(define-public (set-min-reward (new-min uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (> new-min u0) ERR-INVALID-INPUT)
    (var-set min-reward new-min)
    (ok true)
  )
)

(begin
  (var-set platform-fee u2)
  (var-set min-reward u10000)
)