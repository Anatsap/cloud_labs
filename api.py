from flask import Flask, jsonify
from flask_sqlalchemy import SQLAlchemy
from flask_restful import Resource, Api, reqparse, fields, marshal_with, abort
from flask_cors import CORS
from sqlalchemy import desc, asc, func, text
import os
from flasgger import Swagger
app = Flask(__name__)
CORS(app) 

# app.config["SQLALCHEMY_DATABASE_URI"] = "sqlite:///database.db"
app.config["SQLALCHEMY_DATABASE_URI"] = os.environ.get("DATABASE_URL", "sqlite:///database.db")
app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False
db = SQLAlchemy(app)
api = Api(app)
swagger = Swagger(app)



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


class Cars(Resource):
    @marshal_with(carFields)
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
        query = CarModel.query
        
        query = apply_filters(query, args) 
        sort_order = args.get('sort')
        if sort_order == 'high':
            query = query.order_by(desc(CarModel.price)) 
        elif sort_order == 'low':
            query = query.order_by(asc(CarModel.price)) 

        cars = query.all()
        return cars, 200

    @marshal_with(carFields)
    def post(self):
        """
        Create a car
        ---
        tags: [Cars]
        parameters:
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
        """
        args = car_args.parse_args()
        car = CarModel(brand=args["brand"], engine_power=args["engine_power"], 
                       max_speed=args["max_speed"], img=args["img"], 
                       type=args["type"].lower(), price=args["price"])
        db.session.add(car)
        db.session.commit()
        return car, 201

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
        return car
    
    @marshal_with(carFields)
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
        return "", 204 

    
api.add_resource(Cars, "/api/cars/")
api.add_resource(Car, "/api/cars/<int:id>")
api.add_resource(TotalPrice, "/api/cars/total_price/") 

@app.route("/health")
def health():
    db.session.execute(text("SELECT 1"))
    return {"status": "ok"}, 200

@app.route("/version")
def version():
    return {"version": "2"}, 200

with app.app_context():
    db.create_all()

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)