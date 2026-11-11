from flask import Flask, jsonify, request
from flask_sqlalchemy import SQLAlchemy
from flask_restful import Resource, Api, reqparse, fields, marshal_with, marshal, abort
from flask_cors import CORS
from sqlalchemy import desc, asc, func, text
import os
import json
import uuid
import redis
from azure.servicebus import ServiceBusClient, ServiceBusMessage
from flasgger import Swagger
from flask_jwt_extended import JWTManager, create_access_token, jwt_required
app = Flask(__name__)
CORS(app)

CACHE_ENABLED = os.environ.get("CACHE_ENABLED", "false").lower() == "true"   
ASYNC_WRITES = os.environ.get("ASYNC_WRITES", "false").lower() == "true"      
CACHE_TTL = 45                  
IDEM_TTL = 24 * 60 * 60        
REQUEST_TTL = 24 * 60 * 60      
SERVICEBUS_CONNECTION = os.environ.get("SERVICEBUS_CONNECTION")
QUEUE_NAME = os.environ.get("QUEUE_NAME", "car-writes")

rds = None
if os.environ.get("REDIS_URL"):
    rds = redis.Redis.from_url(os.environ["REDIS_URL"], socket_timeout=0.5, decode_responses=True)
def cache_get(key):
    if not (CACHE_ENABLED and rds):
        return None
    try:
        value = rds.get(key)
        rds.incr("stats:hit" if value else "stats:miss")
        return json.loads(value) if value else None
    except redis.RedisError:
        return None


def cache_set(key, data):
    if CACHE_ENABLED and rds:
        try:
            rds.setex(key, CACHE_TTL, json.dumps(data))
        except redis.RedisError:
            pass


def cache_invalidate():
    if rds:
        try:
            for k in rds.scan_iter("cars:list:*"):
                rds.delete(k)
        except redis.RedisError:
            pass
_sender = None


def send_to_queue(payload):
    global _sender
    if _sender is None:
        client = ServiceBusClient.from_connection_string(SERVICEBUS_CONNECTION)
        _sender = client.get_queue_sender(queue_name=QUEUE_NAME)
    try:
        _sender.send_messages(ServiceBusMessage(json.dumps(payload)))
    except Exception:
        _sender = None  
        raise


# app.config["SQLALCHEMY_DATABASE_URI"] = "sqlite:///database.db"
app.config["SQLALCHEMY_DATABASE_URI"] = os.environ.get("DATABASE_URL", "sqlite:///database.db")
app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False
db = SQLAlchemy(app)
api = Api(app)
swagger = Swagger(app)
app.config["JWT_SECRET_KEY"] = os.environ.get("JWT_SECRET_KEY") or os.urandom(32).hex()
app.config["PROPAGATE_EXCEPTIONS"] = True
jwt = JWTManager(app)

login_args = reqparse.RequestParser()
login_args.add_argument("username", type=str, required=True)
login_args.add_argument("password", type=str, required=True)


class Login(Resource):
    def post(self):
        """
        Get a JWT token
        ---
        tags: [Auth]
        parameters:
          - name: body
            in: body
            required: true
            schema:
              type: object
              properties:
                username: {type: string}
                password: {type: string}
        responses:
          200: {description: Token}
          401: {description: Bad credentials}
        """
        args = login_args.parse_args()
        admin_password = os.environ.get("ADMIN_PASSWORD")
        if admin_password and args["username"] == "admin" and args["password"] == admin_password:
            return {"access_token": create_access_token(identity="admin")}, 200
        return {"message": "Bad credentials"}, 401



class CarModel(db.Model):
    __tablename__ = 'car'
    id = db.Column(db.Integer, primary_key=True)
    brand = db.Column(db.String(80), nullable=False)
    engine_power = db.Column(db.Integer, nullable=False)
    max_speed = db.Column(db.Integer, nullable=False)
    img = db.Column(db.String(200))
    type = db.Column(db.String(80))
    price = db.Column(db.Float, nullable=False)

    def __repr__(self):
        return f"Car(brand = {self.brand}, engine_power = {self.engine_power}, max_speed = {self.max_speed}, img = {self.img}, type = {self.type}, price = {self.price})"



car_args = reqparse.RequestParser()
car_args.add_argument("brand", type=str, required=True, help="Brand can not be blank")
car_args.add_argument("engine_power", type=int, required=True, help="Power can not be blank")
car_args.add_argument("max_speed", type=int, required=True)
car_args.add_argument("img", type=str, required=True)
car_args.add_argument("type", type=str, required=True)
car_args.add_argument("price", type=float, required=True)


car_get_parser = reqparse.RequestParser()
car_get_parser.add_argument("sort", type=str, location='args', help="Sort by price: high or low")
car_get_parser.add_argument("type", type=str, location='args', help="Filter by car type (comma separated)")
car_get_parser.add_argument("search", type=str, location='args', help="Search term for brand or type")
car_get_parser.add_argument("limit", type=int, location='args', help="Max number of cars to return")


carFields = {
    "id": fields.Integer,
    "brand": fields.String,
    "engine_power": fields.Integer,
    "max_speed": fields.Integer,
    "img": fields.String,
    "type": fields.String,
    "price": fields.Float,
}


def apply_filters(query, args):
    filter_types = args.get('type')
    if filter_types:
        type_list = [t.strip().lower() for t in filter_types.split(',')]
        query = query.filter(CarModel.type.in_(type_list))

    search_term = args.get('search')
    if search_term:
        search_pattern = f"%{search_term}%"
        query = query.filter(
            (CarModel.brand.ilike(search_pattern)) |
            (CarModel.type.ilike(search_pattern))
        )
    return query


def create_car(args):
    if ASYNC_WRITES:
        if not (rds and SERVICEBUS_CONNECTION):
            abort(503, message="Черга або Redis не налаштовані")
        request_id = str(uuid.uuid4())
        rds.set(f"req:{request_id}", json.dumps({"status": "queued"}), ex=REQUEST_TTL)
        send_to_queue({
            "request_id": request_id,
            "car": {
                "brand": args["brand"],
                "engine_power": args["engine_power"],
                "max_speed": args["max_speed"],
                "img": args["img"],
                "type": args["type"].lower(),
                "price": args["price"],
            },
        })
        return {"request_id": request_id, "status": "queued"}, 202

    car = CarModel(brand=args["brand"], engine_power=args["engine_power"],
                   max_speed=args["max_speed"], img=args["img"],
                   type=args["type"].lower(), price=args["price"])
    db.session.add(car)
    db.session.commit()
    cache_invalidate()
    return marshal(car, carFields), 201


class Cars(Resource):
    def get(self):
        """
        List cars
        ---
        tags: [Cars]
        responses:
          200:
            description: List of cars
        """
        args = car_get_parser.parse_args()

        key = f"cars:list:{args.get('sort')}:{args.get('type')}:{args.get('search')}:{args.get('limit')}"
        cached = cache_get(key)
        if cached is not None:
            return cached, 200

        query = apply_filters(CarModel.query, args)
        sort_order = args.get('sort')
        if sort_order == 'high':
            query = query.order_by(desc(CarModel.price))
        elif sort_order == 'low':
            query = query.order_by(asc(CarModel.price))

        limit = args.get('limit')
        if limit:
            if not sort_order:
                query = query.order_by(desc(CarModel.id))
            query = query.limit(min(max(limit, 1), 200))

        data = marshal(query.all(), carFields)

        cache_set(key, data)
        return data, 200

    @jwt_required()
    def post(self):
        """
        Create a car
        ---
        tags: [Cars]
        parameters:
          - name: Idempotency-Key
            in: header
            type: string
            required: false
          - name: body
            in: body
            required: true
            schema:
              type: object
              properties:
                brand: {type: string}
                engine_power: {type: integer}
                max_speed: {type: integer}
                img: {type: string}
                type: {type: string}
                price: {type: number}
        responses:
          201:
            description: Created
          202:
            description: Accepted (запис поставлено в чергу)
          409:
            description: Запит із цим ключем ще виконується
        """
        args = car_args.parse_args()

        key = request.headers.get("Idempotency-Key")
        use_key = bool(key and rds)

        if use_key:
            if not rds.set(f"idem:{key}", "processing", nx=True, ex=IDEM_TTL):
                saved = rds.get(f"idem:{key}")
                if saved is None or saved == "processing":
                    return {"message": "Запит із цим ключем ще виконується, повторіть пізніше"}, 409
                saved = json.loads(saved)
                return saved["body"], saved["status"]  

        try:
            body, code = create_car(args)
        except Exception:
            if use_key:
                rds.delete(f"idem:{key}")   
            raise

        if use_key:
            rds.set(f"idem:{key}", json.dumps({"status": code, "body": body}), ex=IDEM_TTL)
        return body, code

class TotalPrice(Resource):
    def get(self):
        args = car_get_parser.parse_args()
        query = CarModel.query

        query = apply_filters(query, args)
        total = query.with_entities(func.sum(CarModel.price)).scalar()
        return jsonify({"total_price": float(total) if total else 0.0})


class Car(Resource):
    @marshal_with(carFields)
    def get(self, id):
        """
        Get a car by id
        ---
        tags: [Car]
        parameters:
          - {name: id, in: path, type: integer, required: true}
        responses:
          200: {description: The car}
          404: {description: Not found}
        """
        car = CarModel.query.filter_by(id=id).first()
        if not car:
            abort(404, "Car not found")
        return car

    @marshal_with(carFields)
    @jwt_required()
    def patch(self, id):
        """
        Update a car by id
        ---
        tags: [Car]
        parameters:
          - {name: id, in: path, type: integer, required: true}
          - name: body
            in: body
            required: true
            schema:
              type: object
              properties:
                brand: {type: string}
                engine_power: {type: integer}
                max_speed: {type: integer}
                img: {type: string}
                type: {type: string}
                price: {type: number}
        responses:
          200: {description: The updated car}
          404: {description: Not found}
        """
        args = car_args.parse_args()
        car = CarModel.query.filter_by(id=id).first()
        if not car:
            abort(404, "Car not found")
        car.brand = args["brand"]
        car.engine_power = args["engine_power"]
        car.max_speed = args["max_speed"]
        car.img = args["img"]
        car.type = args["type"].lower()
        car.price = args["price"]
        db.session.commit()
        cache_invalidate()
        return car

    @marshal_with(carFields)
    @jwt_required()
    def delete(self, id):
        """
        Delete a car by id
        ---
        tags: [Car]
        parameters:
          - {name: id, in: path, type: integer, required: true}
        responses:
          204: {description: Deleted}
          404: {description: Not found}
        """
        car = CarModel.query.filter_by(id=id).first()
        if not car:
            return {"message": "Car not found"}, 404
        db.session.delete(car)
        db.session.commit()
        cache_invalidate()
        return "", 204


api.add_resource(Cars, "/api/cars/")
api.add_resource(Car, "/api/cars/<int:id>")
api.add_resource(TotalPrice, "/api/cars/total_price/")
api.add_resource(Login, "/api/login")

@app.route("/health")
def health():
    db.session.execute(text("SELECT 1"))
    return {"status": "ok"}, 200

@app.route("/version")
def version():
    return {"version": "3"}, 200

@app.route("/cache/stats")
def cache_stats():
    if not (CACHE_ENABLED and rds):
        return {"enabled": False}
    hit = int(rds.get("stats:hit") or 0)
    miss = int(rds.get("stats:miss") or 0)
    return {"enabled": True, "hits": hit, "misses": miss,
            "hit_ratio": hit / (hit + miss) if hit + miss else 0}

@app.route("/api/requests/<request_id>")
def request_status(request_id):
    if not rds:
        return {"message": "Redis not set"}, 503
    value = rds.get(f"req:{request_id}")
    if value is None:
        return {"message": "Not found"}, 404
    return json.loads(value), 200

with app.app_context():
    db.create_all()

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)