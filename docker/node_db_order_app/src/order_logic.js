function createOrder(orderId, customer, item, quantity) {
    return {
        id: orderId,
        customer,
        item,
        quantity,
        status: "CREATED"
    };
}

module.exports = {
    createOrder
};
