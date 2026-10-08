const express = require("express");

const {
    createOrder,
    getOrders,
    getOrderById
} = require("./orders");

const app = express();

app.use(express.json());

app.get("/health", (request, response) => {
    response.status(200).json({
        status: "ok"
    });
});

app.get("/orders", async (request, response) => {
    try {
        const orders = await getOrders();

        response.status(200).json(orders);
    } catch (error) {
        console.error("Failed to get orders:", error);

        response.status(500).json({
            error: "Failed to retrieve orders"
        });
    }
});

app.get("/orders/:id", async (request, response) => {
    const orderId = Number(request.params.id);

    if (!Number.isInteger(orderId) || orderId < 1) {
        response.status(400).json({
            error: "Invalid order ID"
        });

        return;
    }

    try {
        const order = await getOrderById(orderId);

        if (!order) {
            response.status(404).json({
                error: "Order not found"
            });

            return;
        }

        response.status(200).json(order);
    } catch (error) {
        console.error("Failed to get order:", error);

        response.status(500).json({
            error: "Failed to retrieve order"
        });
    }
});

app.post("/orders", async (request, response) => {
    const {
        customer,
        item,
        quantity
    } = request.body;

    if (
        !customer ||
        !item ||
        !Number.isInteger(quantity) ||
        quantity < 1
    ) {
        response.status(400).json({
            error: "Invalid order data"
        });

        return;
    }

    try {
        const order = await createOrder(
            customer,
            item,
            quantity
        );

        response.status(201).json(order);
    } catch (error) {
        console.error("Failed to create order:", error);

        response.status(500).json({
            error: "Failed to create order"
        });
    }
});

module.exports = app;
