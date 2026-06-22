from flask import Flask, request, jsonify
from groq import Groq
from dotenv import load_dotenv
import os, json, re, subprocess
from datetime import datetime

load_dotenv()
app = Flask(__name__)
client = Groq(api_key=os.environ["GROQ_API_KEY"])

ANALYSIS_PROMPT = """Tu es un agent SOAR expert en cybersécurité.
Tu reçois les détails d'une alerte Wazuh.

Règles de décision STRICTES pour l'action :

1. block_ip → UNIQUEMENT si :
   - Plusieurs tentatives SSH échouées (>5) depuis une IP externe
   - Scan de ports détecté
   - Attaque DDoS depuis une IP
   - L IP attaquante EST DIFFÉRENTE de l IP victime
   - Occurrence >= 10

2. lock_account → UNIQUEMENT si :
   - Un compte utilisateur spécifique est explicitement compromis
   - Elevation de privileges non autorisée détectée
   - Accès fichiers sensibles avec compte volé
   - Description mentionne explicitement un compte compromis

3. alert_only → si :
   - Une seule tentative de connexion échouée
   - Modification fichier système (FIM/syscheck)
   - Alerte informationnelle
   - Impossible de déterminer l IP attaquante
   - Occurrence = 1

4. monitor → si :
   - Comportement suspect mais non confirmé
   - Activité inhabituelle sans preuve d attaque

IMPORTANT :
- "User missed password" avec occurrence=1 → alert_only
- "Multiple SSH failures" avec occurrence>=10 → block_ip
- Ne JAMAIS lock_account pour une seule tentative ratée
- FIM (syscheck) → toujours alert_only

Réponds UNIQUEMENT avec un JSON valide sans texte autour :
{
  "gravite": <entier 1-10>,
  "action": "block_ip ou lock_account ou alert_only ou monitor",
  "cible_action": "<IP attaquante si block_ip, nom compte si lock_account, null sinon>",
  "resume": "<2 phrases max expliquant l incident>",
  "recommandation": "<1-2 phrases de remédiation>"
}"""

REPORT_PROMPT = """Tu es un analyste SOC senior.
Génère un rapport professionnel d'incident de cybersécurité en Markdown.
Utilise un style professionnel et technique.

Le rapport DOIT contenir exactement ces sections :

# Incident Response Report

## 1. Executive Summary
- ID de l'incident
- Date et heure de détection
- Niveau de sévérité (Low 1-3 / Medium 4-6 / High 7-8 / Critical 9-10)
- Statut : Open
- Résumé en 2-3 lignes

## 2. Incident Details
- Type d'incident (selon MITRE ATT&CK)
- Source de détection : Wazuh SIEM
- Agent/Machine impactée
- IP victime
- IP attaquante

## 3. Indicators of Compromise (IOCs)
- Adresse IP malveillante
- Technique MITRE ATT&CK et description
- Patterns d'attaque observés

## 4. Timeline of Events
| Heure | Événement |
|-------|-----------|
Construire une timeline réaliste basée sur les données

## 5. Investigation Findings
- Cause racine (Root Cause Analysis)
- Méthode utilisée par l'attaquant
- Impact estimé sur le système

## 6. Actions Performed by SOAR
- Actions automatiques exécutées par le système Mini-SOAR
- Résultat de chaque action

## 7. Impact Assessment
- Confidentialité : impact
- Intégrité : impact
- Disponibilité : impact
- Données potentiellement affectées

## 8. Recommendations
- Au moins 3 recommandations concrètes et techniques

## 9. Conclusion
- Résumé de la gestion de l'incident
- Niveau de risque résiduel
- Prochaines étapes"""

@app.route("/health", methods=["GET"])
def health():
    return jsonify({"status": "ok"})

@app.route("/analyser", methods=["POST"])
def analyser():
    data = request.json

    attacker_ip = data.get('attacker_ip', data.get('srcip', 'N/A'))
    victim_ip = data.get('srcip', 'N/A')

    analysis_prompt = f"""{ANALYSIS_PROMPT}

Analyse cette alerte Wazuh :
- Niveau de menace : {data.get('threat_level')}
- Technique MITRE ATT&CK : {data.get('mitre_id')}
- Description : {data.get('summary')}
- Machine victime (agent) : {data.get('agent_name')}
- IP de la machine victime : {victim_ip}
- IP de l attaquant : {attacker_ip}
- Nombre d occurrences : {data.get('occurrence_count', 1)}

Note : Si l IP attaquante est différente de l IP victime,
privilégie block_ip pour bloquer l attaquant.
Si le compte de la victime est compromis, utilise lock_account."""

    try:
        response = client.chat.completions.create(
            model="llama-3.3-70b-versatile",
            messages=[{"role": "user", "content": analysis_prompt}],
            max_tokens=600
        )
        text = response.choices[0].message.content.strip()
        text = re.sub(r'```json|```', '', text).strip()
        verdict = json.loads(text)
    except Exception as e:
        verdict = {
            "gravite": 5,
            "action": "alert_only",
            "cible_action": None,
            "resume": f"Erreur analyse: {str(e)[:100]}",
            "recommandation": "Verifier manuellement."
        }

    report_prompt = f"""{REPORT_PROMPT}

Génère le rapport pour cet incident :
- ID incident : INC-{datetime.now().strftime('%Y%m%d%H%M%S')}
- Date détection : {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}
- Gravité IA : {verdict['gravite']}/10
- Type d attaque : {data.get('summary')}
- Technique MITRE : {data.get('mitre_id')}
- Machine victime : {data.get('agent_name')}
- IP victime : {victim_ip}
- IP attaquant : {attacker_ip}
- Action SOAR : {verdict['action']}
- Cible de l action : {verdict.get('cible_action', 'N/A')}
- Recommandation : {verdict.get('recommandation', 'N/A')}
- Occurrences : {data.get('occurrence_count', 1)}"""

    try:
        report_response = client.chat.completions.create(
            model="llama-3.3-70b-versatile",
            messages=[{"role": "user", "content": report_prompt}],
            max_tokens=2000
        )
        rapport = report_response.choices[0].message.content
    except Exception as e:
        rapport = f"Erreur rapport: {str(e)}"

    verdict["rapport"] = rapport
    verdict["attacker_ip"] = attacker_ip
    verdict["victim_ip"] = victim_ip
    return jsonify(verdict)

@app.route("/bloquer_ip", methods=["POST"])
def bloquer_ip():
    data = request.json
    ip = data.get("ip")
    if not ip:
        return jsonify({"status": "error", "message": "IP manquante"})
    try:
        result = subprocess.run(
            ["sudo", "iptables", "-A", "INPUT", "-s", ip, "-j", "DROP"],
            capture_output=True, text=True
        )
        return jsonify({
            "status": "blocked",
            "ip": ip,
            "message": f"IP {ip} bloquee avec succes"
        })
    except Exception as e:
        return jsonify({"status": "error", "message": str(e)})

@app.route("/lock_account", methods=["POST"])
def lock_account():
    data = request.json
    user = data.get("user", "unknown")
    try:
        result = subprocess.run(
            ["sudo", "usermod", "-L", user],
            capture_output=True, text=True
        )
        return jsonify({
            "status": "locked",
            "user": user,
            "message": f"Compte {user} verrouille avec succes"
        })
    except Exception as e:
        return jsonify({"status": "error", "message": str(e)})

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8000)
