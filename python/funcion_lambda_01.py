import json
def lambda_handler(event, context):  # Corregido: usa 'lambda_handler' como default en consola
    path = event.get("path", "/")
    if path.startswith("/health"):
        return {
            "statusCode": 200,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps({"status": "ok", "service": "lambda-<alias>"})
        }
    if path.startswith("/orders"):
        return {
            "statusCode": 200,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps({
                "orders": [
                    {"id": 1, "item": "book", "qty": 2},
                    {"id": 2, "item": "pen", "qty": 5}
                ]
            })
        }
    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps({"message": "Hello from Lambda via ALB→NLB→API GW"})
    }
