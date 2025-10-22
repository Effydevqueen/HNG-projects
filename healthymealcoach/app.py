from flask import Flask, jsonify, request

app = Flask(__name__)

# Simulated data storage (in-memory)
user_data = {
    "start_weight": None,
    "current_weight": None,
    "goal_weight": None,
    "week": 1
}

# Sample meal suggestions
meal_suggestions = [
    {"meal": "Grilled chicken breast with quinoa and spinach", "type": "high-protein"},
    {"meal": "Lentil soup with whole-grain bread", "type": "high-fibre"},
    {"meal": "Omelette with avocado and mixed veggies", "type": "high-protein"},
    {"meal": "Chickpea salad with olive oil dressing", "type": "high-fibre"},
    {"meal": "Greek yogurt with chia seeds and berries", "type": "high-protein"},
]

@app.route('/')
def home():
    return jsonify({
        "message": "Welcome to HealthyMeal Coach API 🌱",
        "routes": ["/set-goal", "/update-weight", "/progress", "/suggest-meal"]
    })

@app.route('/set-goal', methods=['POST'])
def set_goal():
    data = request.get_json()
    if not data or not all(k in data for k in ("start_weight", "goal_weight")):
        return jsonify({"error": "Provide start_weight and goal_weight"}), 400

    user_data["start_weight"] = data["start_weight"]
    user_data["goal_weight"] = data["goal_weight"]
    user_data["current_weight"] = data["start_weight"]
    user_data["week"] = 1

    return jsonify({"message": "Goal set successfully!", "data": user_data}), 201

@app.route('/update-weight', methods=['POST'])
def update_weight():
    data = request.get_json()
    if not data or "current_weight" not in data:
        return jsonify({"error": "Provide current_weight"}), 400

    user_data["current_weight"] = data["current_weight"]
    user_data["week"] += 1
    return jsonify({"message": "Weight updated!", "data": user_data})

@app.route('/progress', methods=['GET'])
def get_progress():
    if user_data["start_weight"] is None:
        return jsonify({"error": "No goal set yet."}), 400

    progress = user_data["start_weight"] - user_data["current_weight"]
    goal_diff = user_data["start_weight"] - user_data["goal_weight"]
    percent = round((progress / goal_diff) * 100, 2) if goal_diff > 0 else 0

    return jsonify({
        "week": user_data["week"],
        "current_weight": user_data["current_weight"],
        "progress_kg": progress,
        "goal_progress": f"{percent}% achieved"
    })

@app.route('/suggest-meal', methods=['GET'])
def suggest_meal():
    if user_data["current_weight"] is None:
        return jsonify({"error": "Set your goal and update weight first."}), 400

    # Alternate between high-protein and high-fibre weekly
    suggestion_type = "high-protein" if user_data["week"] % 2 != 0 else "high-fibre"
    suggestions = [m for m in meal_suggestions if m["type"] == suggestion_type]
    return jsonify({
        "week": user_data["week"],
        "suggestion_type": suggestion_type,
        "meals": [m["meal"] for m in suggestions]
    })

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)

