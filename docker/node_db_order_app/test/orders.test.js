const test = require("node:test");
const assert = require("node:assert");

const {
    createOrder
} = require("../src/order_logic");

test("createOrder creates an order", () => {
    const order = createOrder(
        1,
        "Mark",
        "Laptop",
        1
    );

    assert.strictEqual(order.customer, "Mark");
    assert.strictEqual(order.item, "Laptop");
    assert.strictEqual(order.quantity, 1);
    assert.strictEqual(order.status, "CREATED");
});
