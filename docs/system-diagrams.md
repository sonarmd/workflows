# CI/CD Pipeline — triggr_api

How code gets from a developer's laptop into a running container in AWS.

```mermaid
flowchart TD
    subgraph DEVELOPER["1. Developer Workstation"]
        main["main branch\n= production\nsource of truth"]
        release["Branch: release/v4.5\nbranched from main\nshared integration branch"]
        feature["Branch: feature/SONMD-1234\nbranched from release\none branch per ticket"]
        work["Write code\ncommit, push"]

        main -. "branch off for\nnew release cycle" .-> release
        release -. "branch off for\neach ticket" .-> feature
        work --> feature
    end

    subgraph GITHUB["2. GitHub — sonarmd/triggr_api"]
        pr["Open PR\nfeature → release branch"]
        checks{"All gates pass?"}
        review{"Peer review\n2 approvals?"}
        merge["Merge PR\ninto release branch"]

        pr --> checks
        checks -- "fail" --> fix["Fix and re-push"]
        fix --> checks
        checks -- "pass" --> review
        review -- "approved" --> merge
    end

    subgraph GHA["3. GitHub Actions — CI Runner"]
        direction TB
        ci_trigger["Triggered by: PR opened/updated"]
        lint["yarn lint\nyarn typecheck"]
        test["yarn test\n4 parallel shards\neach with its own\nMongoDB 8.0 sidecar"]
        build["yarn build\ntsc → dist/"]
        docker["docker build\nmulti-stage\nnode:18-alpine\nResult: Docker image\ntagged with commit SHA"]
        push_ghcr["Push image to\nGitHub Container Registry\nghcr.io/sonarmd/triggr-api:SHA"]

        ci_trigger --> lint & test
        lint & test --> build --> docker --> push_ghcr
    end

    subgraph ANSIBLE["4. Ansible Deploy Server — The Bridge"]
        direction TB
        pull_trigger["Triggered by:\ntag push on release branch\nstg-api-4.5.0-b1"]
        pull_image["Pull image from GHCR\nghcr.io/sonarmd/triggr-api:SHA\n\nAnsible reaches OUT to GitHub\nGitHub does not reach IN to AWS"]
        push_ecr["Push image to ECR\naws ecr get-login-password\ndocker tag → docker push\n\nImage is now inside AWS\nidentical bytes, new address"]
        secrets["Load secrets\nfrom Ansible Vault\n32 secrets per environment\n\nmongo_password\nsession_secret\ntwilio_auth_token\nredis_auth_token\n..."]
        env_vars["Load env vars\nfrom group_vars\n85 cleartext config values\n\nMONGO_URI\nAPI_URL\nITERABLE_CUSTOM_SMS_CAMPAIGN\n..."]
        taskdef["Build ECS Task Definition\n\nWhich image to run:\n  ECR image URI + SHA tag\nWhat env vars to inject:\n  85 cleartext + 32 secrets\nHow much compute:\n  512 CPU / 1024 MB (dev/stg)\n  1024 CPU / 2048 MB (prd)\nWhere to log:\n  CloudWatch /ecs/triggr-api-ENV"]
        register["Register task definition\nwith ECS\n\naws ecs register-task-definition"]
        update_svc["Update ECS service\nto use new task definition\n\naws ecs update-service\n  --force-new-deployment"]

        pull_trigger --> pull_image --> push_ecr
        secrets & env_vars --> taskdef
        push_ecr --> taskdef
        taskdef --> register --> update_svc
    end

    subgraph ECR_DETAIL["5. ECR — Elastic Container Registry"]
        direction TB
        ecr_repo["Repository: sonarmd/triggr-api\n\nA private Docker registry\ninside your AWS account.\nImages stored encrypted.\nOnly accessible from within AWS."]
        ecr_tags["Image tags:\n  :latest\n  :abc123f  ← commit SHA\n  :stg-api-4.5.0-b1\n\nEach tag points to the\nsame image layers.\nLayers are deduplicated."]
        ecr_lifecycle["Lifecycle policy:\nKeep last 20 images\nOlder images auto-expire\nScan on push for CVEs"]

        ecr_repo --- ecr_tags --- ecr_lifecycle
    end

    subgraph ECS_BOOT["6. ECS Fargate — Container Startup"]
        direction TB
        ecs_svc["ECS Service receives\nnew task definition\n\nStarts new task(s)\nbefore stopping old ones\n(rolling deployment)"]
        ecs_pull["Fargate pulls image\nfrom ECR\n\nECR → Fargate is internal\nNo internet required\nVPC endpoint or private link"]
        ecs_env["Container starts with\nall 117 env vars injected\nby ECS from the task definition\n\nThese are in memory only.\nNot on disk. Not in the image."]
        entrypoint["docker-entrypoint.sh runs:\n\n1. node generate-config.js\n   reads all env vars\n   writes configuration.json\n   to /app/configuration.json\n\n2. exec node dist/server.js\n   app starts on :1337\n   reads configuration.json"]
        health["ALB health check\nGET /health every 30s\n\nFirst check after 60s grace\n3 consecutive passes = healthy\nTraffic starts flowing"]

        ecs_svc --> ecs_pull --> ecs_env --> entrypoint --> health
    end

    subgraph PROD["7. Production Promotion"]
        stg_valid["Staging validated\nmanual testing complete"]
        merge_main["Merge release → main\nmain stays in sync with prod"]
        tag_prd["Create tag:\nprd-api-4.5.0\n\nRequires GitHub\nEnvironment approval"]
        same_image["SAME Docker image\nSAME bytes, SAME SHA\nDifferent env vars only\n\nNo rebuild. No new artifact.\nJust promote."]

        stg_valid --> merge_main --> tag_prd --> same_image
    end

    feature --> pr
    merge --> ci_trigger
    push_ghcr --> pull_trigger
    update_svc --> ecs_svc
    push_ecr --> ecr_repo
    ecr_repo --> ecs_pull
    same_image --> pull_trigger
