import os
from flask import Flask, render_template, request, jsonify
import stripe
import requests
from dotenv import load_dotenv

load_dotenv()

app = Flask(__name__)
stripe.api_key = os.getenv("STRIPE_SECRET_KEY")
GOOGLE_MAPS_API_KEY = os.getenv("GOOGLE_MAPS_API_KEY")

# Centro de Distribuição da Empresa (Exemplo: Marília/SP)
ORIGIN_ADDRESS = "Av. das Esmeraldas, Marília - SP"

@app.route("/")
def index():
    return render_template("checkout.html", stripe_public_key=os.getenv("STRIPE_PUBLIC_KEY"))

@app.route("/api/calcular-frete", methods=["POST"])
def calcular_frete():
    data = request.json
    destino = data.get("endereco_destino")

    # Chamada à Distance Matrix API do Google Maps
    url = "https://maps.googleapis.com/maps/api/distancematrix/json"
    params = {
        "origins": ORIGIN_ADDRESS,
        "destinations": destino,
        "mode": "driving",
        "key": GOOGLE_MAPS_API_KEY
    }
    
    response = requests.get(url, params=params)
    resultado = response.json()

    if resultado["status"] != "OK":
        return jsonify({"erro": "Não foi possível calcular a rota para o endereço informado."}), 400

    elemento = resultado["rows"][0]["elements"][0]
    if elemento["status"] != "OK":
        return jsonify({"erro": "Endereço de destino inválido ou inacessível por rotas terrestres."}), 400

    distancia_km = elemento["distance"]["value"] / 1000.0  # Convertendo para KM
    duracao = elemento["duration"]["text"]

    # Regra de negócio: Proibido Correios -> Cálculo exclusivo para Transportadora Privada/Frota Própria
    # Exemplo de taxa: R$ 15,00 fixa + R$ 2,50 por km
    valor_frete = 15.0 + (distancia_km * 2.50)

    return jsonify({
        "distancia_km": round(distancia_km, 2),
        "tempo_estimado": duracao,
        "valor_frete": round(valor_frete, 2),
        "modalidade": "Transportadora Rodoviária Privada (Exclusivo - Sem Correios)"
    })

@app.route("/criar-checkout-session", methods=["POST"])
def criar_checkout_session():
    try:
        data = request.json
        valor_produto = data.get("valor_produto")
        valor_frete = data.get("valor_frete")
        total_centavos = int((valor_produto + valor_frete) * 100)

        session = stripe.checkout.Session.create(
            payment_method_types=["card"],
            line_items=[{
                "price_data": {
                    "currency": "brl",
                    "product_data": {
                        "name": "Pedido E-commerce (Produto + Frete Especializado)",
                    },
                    "unit_amount": total_centavos,
                },
                "quantity": 1,
            }],
            mode="payment",
            success_url="http://localhost:5000/sucesso",
            cancel_url="http://localhost:5000/cancelado",
        )
        return jsonify({"id": session.id})
    except Exception as e:
        return jsonify(error=str(e)), 403

if __name__ == "__main__":
    app.run(debug=True)

