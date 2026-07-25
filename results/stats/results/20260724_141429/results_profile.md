# Results Profile

Generated: 2026-07-24 14:14:29

## Overview

- Models: 16
- Items: 201
- Total responses: 3216
- Tasks: tom_12dim_freeresponse, tom_12dim_mcq
- Families: Llama, Mistral, Qwen

## Model accuracy (Wilson 95% CI)

- llama-3.1-8b-instruct: 0.851 [0.795, 0.893] (n=201)
- llama-2-13b-chat: 0.348 [0.286, 0.416] (n=201)
- llama-2-7b-chat: 0.582 [0.513, 0.648] (n=201)
- llama-3-70b-instruct: 0.970 [0.936, 0.986] (n=201)
- llama-3-8b-instruct: 0.846 [0.789, 0.889] (n=201)
- qwen2.5-7b-instruct: 0.876 [0.823, 0.914] (n=201)
- qwen2.5-72b-instruct: 0.000 [0.000, 0.019] (n=201)
- qwen-1.5-72b-chat: 0.861 [0.806, 0.902] (n=201)
- qwen1.5-7b-chat: 0.657 [0.589, 0.719] (n=201)
- qwen2-72b-instruct: 0.970 [0.936, 0.986] (n=201)
- qwen2-7b-instruct: 0.856 [0.800, 0.898] (n=201)
- qwen2.5-32b-instruct: 0.900 [0.851, 0.935] (n=201)
- mistral-7b-instruct: 0.582 [0.513, 0.648] (n=201)
- mistral-7b-instruct-v0.2: 0.577 [0.508, 0.643] (n=201)
- mistral-7b-instruct-v0.3: 0.289 [0.230, 0.355] (n=201)
- mixtral-8x7b-instruct: 0.000 [0.000, 0.019] (n=201)

## Dimension difficulty (hardest first)

- First-Order False Belief: mean=0.524, sd=0.356
- Faux Pas Detection: mean=0.524, sd=0.319
- Second-Order False Belief: mean=0.526, sd=0.359
- Sarcasm: mean=0.558, sd=0.334
- Knowledge Access / Ignorance: mean=0.633, sd=0.311
- White Lies / Prosocial Deception: mean=0.642, sd=0.318
- Intention vs. Accident: mean=0.646, sd=0.346
- Hidden Emotion (Appearance vs. Reality): mean=0.649, sd=0.335
- Diverse Beliefs: mean=0.694, sd=0.354
- Irony: mean=0.729, sd=0.351
- Diverse Desires: mean=0.733, sd=0.357
- Emotion Recognition: mean=0.820, sd=0.335

## Reliability (KR-20)

- tom_12dim_freeresponse: KR-20=0.9826 (n_items=60, n_models=16)
- tom_12dim_mcq: KR-20=0.9946 (n_items=141, n_models=16)
