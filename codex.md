# SamaFox System

This is a full-stack real-time voice room application.

## Structure
- backend/ → Node.js + Express + Prisma + Socket.io
- app/ → Flutter mobile app

## Core Features
- Voice chat rooms
- Mic seat system
- Real-time socket sync
- Admin controls
- Messaging & gifts

## Backend Responsibilities
- Manage rooms, users, seats
- Handle socket events
- Broadcast real-time updates
- Persist data with Prisma

## App Responsibilities
- Display rooms UI
- Listen to socket events
- Send user actions (join seat, leave, mic)
- Sync UI with backend state

## Critical Rule
Whenever modifying a feature:
- ALWAYS update BOTH backend and app if needed
- Keep socket event names consistent
- Ensure real-time sync is correct

## Socket Rules
- Every backend emit must have matching listener in Flutter
- No UI update without backend confirmation
- Avoid duplicate emits

## Goals
- Zero mismatch between backend and app
- Stable real-time sync
- Scalable architecture (Redis-ready)
