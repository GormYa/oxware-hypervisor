import json
import hashlib
import hmac
import os
import base64
import secrets
import time
from functools import wraps
from flask import request, jsonify
from flask_jwt_extended import (
    create_access_token, verify_jwt_in_request,
    get_jwt_identity, get_jwt
)
import config

ROLES = {
    "administrator": ["*"],
    "operator": ["vm.*", "storage.read", "network.read", "system.read"],
    "viewer": ["*.read", "system.read"],
    "vm-user": ["vm.read"],   # only assigned VMs via filtering
}

_PBKDF2_ITER = 260_000


def _hash_password(password: str) -> str:
    """
    Salt + PBKDF2-SHA256.
    Format: pbkdf2_sha256$<iterations>$<b64salt>$<b64hash>
    """
    salt = os.urandom(32)
    dk   = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), salt, _PBKDF2_ITER)
    return (
        f"pbkdf2_sha256${_PBKDF2_ITER}"
        f"${base64.b64encode(salt).decode()}"
        f"${base64.b64encode(dk).decode()}"
    )


def _verify_hash(password: str, stored: str) -> bool:
    """
    Verify password against stored hash.
    Supports both new pbkdf2_sha256 format and legacy plain sha256 (migration path).
    """
    if stored.startswith("pbkdf2_sha256$"):
        try:
            _, iterations_s, b64_salt, b64_hash = stored.split("$")
            salt    = base64.b64decode(b64_salt)
            dk      = hashlib.pbkdf2_hmac(
                "sha256", password.encode("utf-8"), salt, int(iterations_s)
            )
            # constant-time comparison
            return hmac.compare_digest(base64.b64decode(b64_hash), dk)
        except Exception:
            return False
    # Legacy: plain sha256 (backward compat — migrated on next login)
    return hmac.compare_digest(
        hashlib.sha256(password.encode()).hexdigest(),
        stored
    )


def _load_users():
    if not os.path.exists(config.USERS_FILE):
        # Generate random first-boot password instead of hardcoded default
        first_password = secrets.token_urlsafe(16)
        users = {
            "admin": {
                "password":              _hash_password(first_password),
                "role":                  "administrator",
                "created":               time.time(),
                "must_change_password":  True,
            }
        }
        _save_users(users)
        print(
            f"\n{'='*60}\n"
            f"  OXware İlk Kurulum — Admin Şifresi\n"
            f"  Kullanıcı adı : admin\n"
            f"  Şifre         : {first_password}\n"
            f"  Bu şifreyi kaydedin! İlk girişte değiştirmeniz istenecek.\n"
            f"{'='*60}\n",
            flush=True
        )
        return users
    with open(config.USERS_FILE) as f:
        users = json.load(f)
    # Migrate legacy plain-sha256 hashes on load
    migrated = False
    for uname, udata in users.items():
        stored = udata.get("password", "")
        if stored and not stored.startswith("pbkdf2_sha256$"):
            # Can't rehash without plaintext — mark for forced reset
            udata["legacy_hash"] = True
    if migrated:
        _save_users(users)
    return users


def _save_users(users):
    os.makedirs(os.path.dirname(config.USERS_FILE), exist_ok=True)
    with open(config.USERS_FILE, "w") as f:
        json.dump(users, f, indent=2)
    try:
        os.chmod(config.USERS_FILE, 0o600)
    except OSError:
        pass


def verify_password(username, password):
    users = _load_users()
    user  = users.get(username)
    if not user:
        return False
    ok = _verify_hash(password, user.get("password", ""))
    # Auto-upgrade legacy hash on successful login
    if ok and not user.get("password", "").startswith("pbkdf2_sha256$"):
        users[username]["password"] = _hash_password(password)
        users[username].pop("legacy_hash", None)
        _save_users(users)
    return ok


def get_user(username):
    users = _load_users()
    return users.get(username)


def list_users():
    users = _load_users()
    return [
        {
            "username":             u,
            "role":                 d.get("role", "viewer"),
            "created":              d.get("created"),
            "must_change_password": d.get("must_change_password", False),
        }
        for u, d in users.items()
    ]


def create_user(username, password, role="operator"):
    users = _load_users()
    if username in users:
        raise ValueError(f"Kullanıcı zaten mevcut: {username}")
    users[username] = {
        "password": _hash_password(password),
        "role":     role,
        "created":  time.time(),
    }
    _save_users(users)


def delete_user(username):
    users = _load_users()
    if username not in users:
        raise ValueError(f"Kullanıcı bulunamadı: {username}")
    if username == "admin":
        raise ValueError("Admin kullanıcısı silinemez")
    del users[username]
    _save_users(users)


def change_password(username, new_password):
    users = _load_users()
    if username not in users:
        raise ValueError(f"Kullanıcı bulunamadı: {username}")
    users[username]["password"]             = _hash_password(new_password)
    users[username]["must_change_password"] = False
    users[username].pop("legacy_hash", None)
    _save_users(users)


def jwt_required_role(*allowed_roles):
    def decorator(fn):
        @wraps(fn)
        def wrapper(*args, **kwargs):
            try:
                verify_jwt_in_request()
            except Exception:
                return jsonify({"error": "Kimlik doğrulama gerekli"}), 401

            identity = get_jwt_identity()
            user     = get_user(identity)
            if not user:
                return jsonify({"error": "Kullanıcı bulunamadı"}), 401

            role = user.get("role", "viewer")
            if allowed_roles and role not in allowed_roles and role != "administrator":
                return jsonify({"error": "Yetersiz yetki"}), 403

            return fn(*args, **kwargs)
        return wrapper
    return decorator


def require_auth(fn):
    @wraps(fn)
    def wrapper(*args, **kwargs):
        try:
            verify_jwt_in_request()
        except Exception:
            return jsonify({"error": "Kimlik doğrulama gerekli"}), 401
        return fn(*args, **kwargs)
    return wrapper
