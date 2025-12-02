#!/bin/bash

# QUICK START GUIDE - Exécuter cela après git clone
# ================================================

set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║  🚀 ODOO BACKUP/RESTORE INFRASTRUCTURE - QUICK START       ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Step 1: Check if .env exists
if [ ! -f "$PROJECT_DIR/.env" ]; then
    echo "📋 Step 1: Créer le fichier .env..."
    cp "$PROJECT_DIR/.env.example" "$PROJECT_DIR/.env"
    echo "✅ Fichier .env créé"
    echo ""
    echo "⚠️  IMPORTANT: Éditer maintenant le fichier .env avec vos credentials R2:"
    echo "   nano .env"
    echo ""
    echo "   À remplir absolument:"
    echo "   - POSTGRES_PASSWORD"
    echo "   - ODOO_ADMIN_PASSWORD"
    echo "   - CF_R2_ENDPOINT"
    echo "   - CF_R2_BUCKET"
    echo "   - CF_R2_ACCESS_KEY_ID"
    echo "   - CF_R2_SECRET_ACCESS_KEY"
    echo ""
    read -p "Appuyez sur ENTRÉE quand .env est rempli..."
fi

# Step 2: Verify .env is configured
if grep -q "your_secure_password_here\|your_r2_access_key_id" "$PROJECT_DIR/.env"; then
    echo "❌ ERREUR: Le fichier .env contient encore des valeurs par défaut"
    echo "   Veuillez éditer .env avec vos vraies valeurs"
    exit 1
fi

echo "📋 Step 2: Préparation de l'infrastructure..."
chmod +x "$PROJECT_DIR/scripts"/*.sh
echo "✅ Scripts rendus exécutables"

# Step 3: Run setup
echo ""
echo "📋 Step 3: Exécution du setup (peut prendre 3-5 minutes)..."
echo ""
"$PROJECT_DIR/scripts/setup.sh"

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║  ✅ SETUP TERMINÉ AVEC SUCCÈS                             ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "🎯 Prochaines étapes:"
echo ""
echo "1. Accéder à Odoo:"
echo "   → http://localhost"
echo ""
echo "2. Sauvegarde manuelle:"
echo "   → ./scripts/backup.sh"
echo ""
echo "3. Restauration depuis backup:"
echo "   → ./scripts/restore.sh <backup-name>"
echo ""
echo "4. Voir les logs:"
echo "   → tail -f /var/log/odoo-backup.log"
echo ""
echo "5. Pour plus d'infos:"
echo "   → cat README.md"
echo ""
