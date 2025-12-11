# jwt_auth.py
"""
JWT auth helpers for Wishnode — clean, safe, circular-import-proof.

Exports:
 - create_token_for_user(user_id, expires_in)
 - decode_token(token)
 - set_auth_cookie(response, ...)
 - make_auth_dependencies(get_db)
 - user_from_token(db, token)
"""

import os
from datetime import datetime, timedelta, timezone
from typing import Callable, Dict, Any, Optional
from sqlalchemy.orm import Session

import jwt
from jwt import InvalidTokenError

from fastapi import Depends, HTTPException, Request, Response
from fastapi import status

# ---------------------------------------------------------
# Configuration
# ---------------------------------------------------------
JWT_SECRET = os.getenv("JWT_SECRET", "PLEASE-CHANGE-IN-PRODUCTION")
JWT_ALG = os.getenv("JWT_ALG", "HS256")
JWT_EXP_SECONDS = int(os.getenv("JWT_EXP_SECONDS", str(60 * 60 * 24 * 365)))  # 1 year
AUTH_COOKIE_NAME = os.getenv("AUTH_COOKIE_NAME", "wishnode_token")
DEV_FLAG = os.getenv("DEV", "1") == "1"


# ---------------------------------------------------------
# Token creation / decoding (no DB here)
# ---------------------------------------------------------
def create_token_for_user(user_id: str, expires_in: int = JWT_EXP_SECONDS) -> str:
    """
    Create and sign a JWT for a given user_id.
    """
    now = datetime.now(timezone.utc)
    payload = {
        "sub": str(user_id),
        "iat": int(now.timestamp()),
        "exp": int((now + timedelta(seconds=expires_in)).timestamp()),
        "typ": "access",
    }

    token = jwt.encode(payload, JWT_SECRET, algorithm=JWT_ALG)
    if isinstance(token, bytes):
        token = token.decode("utf-8")
    return token


def decode_token(token: str) -> Dict[str, Any]:
    """
    Decode and verify a token; raises InvalidTokenError on failure.
    """
    if not token:
        raise InvalidTokenError("empty token")
    return jwt.decode(token, JWT_SECRET, algorithms=[JWT_ALG])


def set_auth_cookie(response: Response, token: str, max_age: int = JWT_EXP_SECONDS):
    """
    Set the auth cookie. Uses secure=False in dev for localhost.
    """
    secure_flag = not DEV_FLAG
    response.set_cookie(
        AUTH_COOKIE_NAME,
        token,
        httponly=True,
        samesite="Lax",
        secure=secure_flag,
        max_age=max_age,
    )


# ---------------------------------------------------------
# Main dependency factory (avoids circular imports)
# ---------------------------------------------------------
def make_auth_dependencies(get_db: Callable[[], Any]):
    """
    Call this after get_db() exists in your main.

    Returns:
        {
          "get_current_user": dependency requiring valid token,
          "get_current_user_optional": dependency returning User or None
        }
    """

    # Lazy import to avoid circular dependencies
    try:
        from models import User, Tier
    except Exception as e:
        raise RuntimeError("Could not import models inside jwt_auth: " + str(e))

    def _extract_token(request: Request) -> Optional[str]:
        # Authorization header first
        header = request.headers.get("Authorization")
        if header:
            parts = header.split()
            if len(parts) == 2 and parts[0].lower() == "bearer":
                return parts[1]

        # Then cookie
        return request.cookies.get(AUTH_COOKIE_NAME)

    # -------- REQUIRED ----------
    def get_current_user(
        request: Request,
        db: Session = Depends(get_db)
    ):
        token = _extract_token(request)
        if not token:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Missing authentication token",
            )

        try:
            payload = decode_token(token)
        except InvalidTokenError:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid or expired token",
            )

        user_id = payload.get("sub")
        if not user_id:
            raise HTTPException(
                status_code=401,
                detail="Invalid token payload (missing sub)"
            )

        # Create anon user if token references user not yet in DB
        user = db.query(User).filter(User.id == str(user_id)).first()
        if not user:
            user = User(id=str(user_id), tier=Tier.anon)
            db.add(user)
            db.commit()
            db.refresh(user)

        return user

    # -------- OPTIONAL ----------
    def get_current_user_optional(
        request: Request,
        db: Session = Depends(get_db)
    ):
        token = _extract_token(request)
        if not token:
            return None

        try:
            payload = decode_token(token)
        except InvalidTokenError:
            return None

        user_id = payload.get("sub")
        if not user_id:
            return None

        user = db.query(User).filter(User.id == str(user_id)).first()
        if not user:
            user = User(id=str(user_id), tier=Tier.anon)
            db.add(user)
            db.commit()
            db.refresh(user)

        return user

    return {
        "get_current_user": get_current_user,
        "get_current_user_optional": get_current_user_optional,
    }


# ---------------------------------------------------------
# Standalone helper for backend scripts or utilities
# ---------------------------------------------------------
def user_from_token(db: Session, token: str):
    """
    Decode the token and return the corresponding User instance.
    Safe to call from anywhere (admin scripts, etc.)
    """
    # Lazy import here too to avoid circular import
    from models import User

    payload = decode_token(token)
    user_id = payload.get("sub") or payload.get("user_id")
    if not user_id:
        return None

    return db.query(User).filter(User.id == str(user_id)).first()
