# When to Mock

Mock at **system boundaries** only:

- External APIs (payment, email, etc.)
- The model API. The stand-in replays a recorded response or returns a fixed reply, and it, not a temperature of zero, is what makes the test deterministic. The real model is exercised by a scored eval set, not by a unit test.
- Databases and the warehouse (sometimes). Prefer a real test database, or a local engine over fixture tables, to a mock: a mocked query proves nothing about the SQL. When production runs another engine, a green on DuckDB does not cover what engines disagree on even in identical SQL, such as function return types and NULL and date semantics (`DATE_TRUNC('month', <date>)` returns a TIMESTAMP in DuckDB and a DATE in Snowflake); check that behaviour against the production engine.
- Time/randomness
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
