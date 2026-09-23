# Good and Bad Tests

## Good Tests

**Integration-style**: Test through real interfaces, not mocks of internal parts.

```typescript
// GOOD: Tests observable behavior
test("user can checkout with valid cart", async () => {
  const cart = createCart();
  cart.add(product);
  const result = await checkout(cart, paymentMethod);
  expect(result.status).toBe("confirmed");
});
```

Characteristics:

- Tests behavior users/callers care about
- Uses public API only
- Survives internal refactors
- Describes WHAT, not HOW
- One logical assertion per test

## Bad Tests

**Implementation-detail tests**: Coupled to internal structure.

```typescript
// BAD: Tests implementation details
test("checkout calls paymentService.process", async () => {
  const mockPayment = jest.mock(paymentService);
  await checkout(cart, payment);
  expect(mockPayment.process).toHaveBeenCalledWith(cart.total);
});
```

Red flags:

- Mocking internal collaborators
- Testing private methods
- Asserting on call counts/order
- Test breaks when refactoring without behavior change
- Test name describes HOW not WHAT
- Verifying through external means instead of interface

```typescript
// BAD: Bypasses interface to verify
test("createUser saves to database", async () => {
  await createUser({ name: "Alice" });
  const row = await db.query("SELECT * FROM users WHERE name = ?", ["Alice"]);
  expect(row).toBeDefined();
});

// GOOD: Verifies through interface
test("createUser makes user retrievable", async () => {
  const user = await createUser({ name: "Alice" });
  const retrieved = await getUser(user.id);
  expect(retrieved.name).toBe("Alice");
});
```

**Tautological tests**: Expected value restates the implementation, so the test passes by construction.

```typescript
// BAD: Expected value is recomputed the way the code computes it
test("calculateTotal sums line items", () => {
  const items = [{ price: 10 }, { price: 5 }];
  const expected = items.reduce((sum, i) => sum + i.price, 0);
  expect(calculateTotal(items)).toBe(expected);
});

// GOOD: Expected value is an independent, known literal
test("calculateTotal sums line items", () => {
  expect(calculateTotal([{ price: 10 }, { price: 5 }])).toBe(15);
});
```

## The same rules over a table

The seam is the model's output table for a known input table. The expected rows are literals, not a recomputation. Sort before comparing, because a GROUP BY promises no row order, and write each literal in the type the driver returns, because a DATE column comes back as a `date` and never equals a string.

```python
# GOOD: known input table in, literal output rows out
def test_daily_totals_sum_each_day_once(engine):
    load(engine, "orders", [
        {"order_id": 1, "day": date(2026, 1, 1), "amount": 10},
        {"order_id": 2, "day": date(2026, 1, 1), "amount": 5},
        {"order_id": 3, "day": date(2026, 1, 2), "amount": 7},
    ])
    rows = run_model(engine, "daily_totals")
    assert sorted(rows, key=itemgetter("day")) == [
        {"day": date(2026, 1, 1), "total": 15},
        {"day": date(2026, 1, 2), "total": 7},
    ]
```

```python
# BAD: recomputes the expected value from the same input, so it passes by construction
def test_daily_totals(engine):
    orders = load(engine, "orders", fixture_orders)
    expected = sum(o["amount"] for o in orders if o["day"] == "2026-01-01")
    assert run_model(engine, "daily_totals")[0]["total"] == expected

# BAD: verifies through an intermediate table the model does not promise
def test_daily_totals_reads_staging(engine):
    run_model(engine, "daily_totals")
    assert engine.execute("select count(*) from stg_orders").scalar() == 3
```

## The same rules at a model boundary

The seam is the module's interface, not the model API. Against the real model, assert a score over a set, never one string.

```python
# GOOD: a fixed reply from a fake model; the citation filter is under test
def test_answer_drops_a_citation_to_a_passage_it_was_not_given(fake_model):
    fake_model.reply("The limit is 10 per day [2][7].")
    answer = answer_question("what is the limit?", passages=two_passages, model=fake_model)
    assert answer.citations == {2}

# GOOD: an eval over a labelled set, run on its own, never by the test command.
# 0.9 is the measured baseline minus the measured run-to-run noise.
def eval_answers_clear_the_faithfulness_baseline(eval_set, real_model):
    score = run_eval(eval_set, model=real_model)
    assert score.faithfulness >= 0.9
```

```python
# BAD: one exact string from a non-deterministic call
def test_answer(real_model):
    assert answer_question("what is the limit?", model=real_model).text == "The limit is 10 per day."
```
