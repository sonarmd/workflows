#!/usr/bin/env bash
#
# layer-classify.sh — classify a source file into a Clean Architecture
# layer using path + filename heuristics. Language-agnostic.
#
# Usage:   layer-classify.sh <file-path>
# Output:  <file-path>\t<layer>
#
# Layers (in dependency direction — top depends on layers below):
#   interface       HTTP handlers, CLI parsers, message consumers
#   application     use cases, services that orchestrate domain ops
#   domain          entities, value objects, aggregates, domain services
#   infrastructure  repositories, DB adapters, external API clients
#   presentation    UI components, views, pages
#   test            test files
#   cross-cutting   config, middleware, shared utilities
#   unknown         heuristics did not match (treat as warning)

set -euo pipefail

F="${1:?usage: layer-classify.sh <file>}"
layer="unknown"

# Order matters — more-specific patterns first.
case "$F" in
  # Tests are always tests, regardless of where they live.
  */test/*|*/tests/*|*/__tests__/*|*/spec/*|*/specs/*) layer="test" ;;
  *_test.go|*_test.py|*.test.ts|*.spec.ts|*.test.tsx|*.spec.tsx|*.test.js|*.spec.js) layer="test" ;;

  # Presentation — user-facing UI.
  */views/*|*/pages/*|*/screens/*) layer="presentation" ;;
  */components/*) layer="presentation" ;;

  # Interface — adapters in, transport layer.
  */controllers/*|*/handlers/*|*/routes/*|*/endpoints/*|*/api/*) layer="interface" ;;
  */cli/*|*/cmd/*|*/commands/*) layer="interface" ;;
  */resolvers/*|*/graphql/*) layer="interface" ;;
  */workers/*|*/consumers/*|*/listeners/*|*/subscribers/*) layer="interface" ;;

  # Application — use cases, application services.
  */use-cases/*|*/usecases/*|*/use_cases/*|*/application/*) layer="application" ;;
  */services/*) layer="application" ;;
  */workflows/*) layer="application" ;;

  # Infrastructure — repositories, external adapters.
  */repositories/*|*/repository/*) layer="infrastructure" ;;
  */adapters/*|*/adapter/*) layer="infrastructure" ;;
  */infrastructure/*|*/infra/*) layer="infrastructure" ;;
  */persistence/*|*/db/*|*/database/*) layer="infrastructure" ;;
  */clients/*|*/gateways/*) layer="infrastructure" ;;

  # Domain — innermost.
  */domain/*|*/entities/*|*/entity/*) layer="domain" ;;
  */aggregates/*|*/aggregate/*) layer="domain" ;;
  */value-objects/*|*/value_objects/*) layer="domain" ;;
  */models/*) layer="domain" ;;  # often domain in DDD-flavored repos

  # Cross-cutting.
  */config/*|*/configs/*|*/configuration/*) layer="cross-cutting" ;;
  */middleware/*|*/middlewares/*) layer="cross-cutting" ;;
  */utils/*|*/util/*|*/helpers/*|*/lib/*) layer="cross-cutting" ;;
  */shared/*|*/common/*) layer="cross-cutting" ;;
esac

printf '%s\t%s\n' "$F" "$layer"
