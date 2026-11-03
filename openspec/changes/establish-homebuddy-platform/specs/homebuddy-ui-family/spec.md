# Spec Delta

## Purpose

Keeps homeBuddy product UIs consistent while making each product recognizable.

## ADDED Requirements

### Requirement: Product UIs share one component anatomy
Every product UI SHALL follow the finanzBuddy design-system anatomy: typography, spacing, sizing, radii, elevation, focus outline, motion, breakpoints, application shell, authentication layout, buttons, fields, selectors, notices, tables, pagination, dialogs, and empty, loading, and error states, using the same CSS token names. Each product SHALL keep its own design-system reference that links to the finanzBuddy reference and records every deviation with its rationale.

#### Scenario: Same control in two products
- **WHEN** a user sees a primary button or a data table in finanzBuddy and in calendarBuddy
- **THEN** shape, size, typography, and interaction states are the same

### Requirement: Each product has its own identity and shared semantics
Each product SHALL have its own primary palette and brand mark, distinguishable from every other product: finanzBuddy teal `#167D68`, calendarBuddy indigo `#4F46B8`. Semantic success, warning, danger, info, and neutral colors SHALL be identical in all products. Every palette SHALL meet WCAG 2.2 AA for its documented text and control pairs.

#### Scenario: Switch between products
- **WHEN** a user opens calendarBuddy after finanzBuddy
- **THEN** the brand and accent color show a different product while errors and warnings look the same

#### Scenario: Add a palette
- **WHEN** a new product introduces its palette
- **THEN** the palette's contrast is verified and it is recorded here with its primary color
