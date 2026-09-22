# When to Mock

Mock at **system boundaries** only:

- External APIs (payment, email, etc.)
- The model API. The stand-in replays a recorded response or returns a fixed reply, and the test asserts on what your module does with that reply, never on the reply itself. The real model is exercised by a scored eval set, not by a unit test.
- Databases and the warehouse (sometimes). Prefer a real test database, or a local engine such as DuckDB over fixture tables, to a mock: a mocked query proves nothing about the SQL.
- Time/randomness, including sampling. A seed, or a temperature of zero where the interface allows it, is part of the fixture.
- File system (sometimes)

Don't mock:

- Your own classes/modules
- Internal collaborators
- Anything you control

## Designing for Mockability

At system boundaries, design interfaces that are easy to mock:

**1. Use dependency injection**

Pass external dependencies in rather than creating them internally:

```typescript
// Easy to mock
function processPayment(order, paymentClient) {
  return paymentClient.charge(order.total);
}

// Hard to mock
function processPayment(order) {
  const client = new StripeClient(process.env.STRIPE_KEY);
  return client.charge(order.total);
}
```

The same move at a model boundary:

```python
# Easy to replace with a fake
def answer_question(question, passages, model):
    return parse(model.complete(build_prompt(question, passages)))

# Hard to replace: the client is built inside
def answer_question(question, passages):
    model = ModelClient(os.environ["MODEL_API_KEY"])
    return parse(model.complete(build_prompt(question, passages)))
```

**2. Prefer SDK-style interfaces over generic fetchers**

Create specific functions for each external operation instead of one generic function with conditional logic:

```typescript
// GOOD: Each function is independently mockable
const api = {
  getUser: (id) => fetch(`/users/${id}`),
  getOrders: (userId) => fetch(`/users/${userId}/orders`),
  createOrder: (data) => fetch('/orders', { method: 'POST', body: data }),
};

// BAD: Mocking requires conditional logic inside the mock
const api = {
  fetch: (endpoint, options) => fetch(endpoint, options),
};
```

The SDK approach means:
- Each mock returns one specific shape
- No conditional logic in test setup
- Easier to see which endpoints a test exercises
- Type safety per endpoint
