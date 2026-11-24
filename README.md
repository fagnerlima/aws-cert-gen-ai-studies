# aws-cert-gen-ai-studies

Código [OpenTofu](https://opentofu.org/) que recria sob demanda a Knowledge Base do Amazon Bedrock usada nos estudos para a certificação AWS de IA generativa.

A Knowledge Base `sundog-rag` guarda os embeddings numa coleção do Amazon OpenSearch Serverless, que **cobra por hora mesmo sem uso**. Por isso ela é criada ao começar a estudar (`scripts/up.sh`) e destruída ao terminar (`scripts/down.sh`), sempre com a mesma configuração.

## Estrutura

| Caminho | O que gerencia | Ciclo de vida |
|---|---|---|
| `persistent/` | Bucket S3 `sundog-franks-book-fl` com o livro (importado do console), bloqueio de acesso público e criptografia | Permanente; `prevent_destroy` no bucket |
| `knowledge-base/` | Role IAM da KB, políticas e coleção do OpenSearch Serverless, índice vetorial, Knowledge Base e data source S3 | Criado e destruído a cada sessão |
| `scripts/up.sh` | `tofu apply` em `knowledge-base/` e ingestão do data source, esperando terminar | — |
| `scripts/down.sh` | `tofu destroy` em `knowledge-base/` e aviso se sobrar coleção do OpenSearch Serverless | — |

Configuração replicada: região `us-east-1`; KB do tipo VECTOR com embedding `amazon.titan-embed-text-v2:0` (1024 dimensões, FLOAT32); coleção VECTORSEARCH sem réplicas standby, criptografada com chave da AWS e com endpoint acessível pela internet (autenticação IAM; sem dashboard); índice `bedrock-knowledge-base-default-index` (HNSW, FAISS, L2); data source `franks-book` com chunking padrão e política de exclusão de dados DELETE.

O state é local (arquivos `terraform.tfstate` em cada diretório, fora do Git). Não apague o state de `knowledge-base/` com a KB criada, senão o `down.sh` não consegue destruí-la. Se gravar um plano em arquivo, use sempre a extensão `.tfplan` (por exemplo, `tofu plan -out=kb.tfplan`), que o `.gitignore` ignora: o plano contém dados da conta.

## Pré-requisitos

- OpenTofu 1.8 ou mais novo (`tofu version`).
- AWS CLI v2 com credenciais padrão configuradas (`aws sts get-caller-identity`).
- Acesso ao modelo `amazon.titan-embed-text-v2:0` no Bedrock em `us-east-1`.
- Permissões para quem roda o Tofu: IAM (criar e apagar a role e a política inline da KB, `iam:PassRole` nela e `iam:GetRole`, usado para descobrir a role por trás de uma sessão assumida), OpenSearch Serverless (`aoss:*` nas coleções e políticas), Bedrock (`bedrock:*KnowledgeBase*`, `bedrock:*DataSource*`, `bedrock:*IngestionJob*`) e S3 (leitura da configuração do bucket). A política gerenciada `AdministratorAccess` cobre tudo isso numa conta de estudos.
- Funciona com usuário IAM, role assumida ou SSO: o ARN de quem roda o Tofu (o usuário, ou a role por trás da sessão) entra na política de acesso a dados do OpenSearch Serverless para que ele possa criar e apagar o índice.

## Primeira vez

1. Importe o bucket existente (só lê a configuração atual e grava no state local; nada muda na conta):

   ```bash
   tofu -chdir=persistent init
   tofu -chdir=persistent plan    # deve mostrar "3 to import, 0 to add, 0 to change, 0 to destroy"
   tofu -chdir=persistent apply
   ```

2. Remova a Knowledge Base e a coleção criadas pelo console (o nome `sundog-rag` da KB precisa estar livre, e a coleção antiga continua cobrando). No console do Bedrock, apague a KB `sundog-rag`; no console do OpenSearch Serverless, apague a coleção `bedrock-knowledge-base-…` e as políticas com o mesmo nome; no IAM, apague a role `AmazonBedrockExecutionRoleForKnowledgeBase_…` e as políticas dela. O bucket fica.

3. Siga o uso diário abaixo.

## Uso diário

Ao começar a estudar:

```bash
scripts/up.sh                 # mostra o plano e pede confirmação
scripts/up.sh -auto-approve   # sem confirmação
```

O script roda `tofu init` se preciso, `tofu apply` (os argumentos são repassados), inicia a ingestão do data source e espera ela terminar, falhando se a ingestão falhar ou passar do tempo limite (`INGESTION_TIMEOUT_SECONDS`, padrão 900; intervalo `INGESTION_POLL_SECONDS`, padrão 15). A criação leva alguns minutos, a maior parte esperando a coleção ficar ativa.

Ao terminar:

```bash
scripts/down.sh               # mostra o que será destruído e pede confirmação
scripts/down.sh -auto-approve
```

Depois do destroy, mesmo que ele falhe, o script lista as coleções do OpenSearch Serverless na região e sai com erro se ainda existir alguma, porque ela continua cobrando. A conferência conta **qualquer** coleção da região, não só a desta KB; uma coleção de outro projeto também faz o script falhar. Sem coleções, ele sai com o código do destroy.

Se o `up.sh` falhar depois de criar recursos, ele avisa que a coleção pode estar cobrando: corrija e rode o `up.sh` de novo, ou rode o `down.sh`. Se já houver uma ingestão em andamento (por exemplo, de uma execução interrompida), o `up.sh` acompanha esse job em vez de iniciar outro; ele também falha se algum documento não for ingerido.

## Se o destroy travar

- **Data source em `DELETE_UNSUCCESSFUL`**: com a política de exclusão DELETE, o Bedrock tenta apagar os vetores do índice antes de apagar o data source e pode falhar (por exemplo, se o índice já sumiu). Mude `data_deletion_policy` para `"RETAIN"` em `knowledge-base/bedrock.tf`, rode `tofu -chdir=knowledge-base apply` e depois o `down.sh` de novo; volte para `"DELETE"` em seguida.
- **Coleção órfã** (o destroy falhou, mas a coleção continua no state ou ficou na conta): apague a coleção pelo console do OpenSearch Serverless, remova do state o que já não existe (por exemplo, `tofu -chdir=knowledge-base state rm opensearch_index.kb aws_opensearchserverless_collection.kb`; veja a lista com `tofu -chdir=knowledge-base state list`) e rode o `down.sh` de novo para destruir o restante.

## Custo

O OpenSearch Serverless cobra por OCU-hora com um mínimo por coleção ativa, mesmo sem consultas, além do armazenamento. Mesmo sem réplicas standby, uma coleção esquecida custa algumas centenas de dólares por mês; confira os valores atuais na [página de preços](https://aws.amazon.com/opensearch-service/pricing/). Rode o `down.sh` sempre que terminar e, se quiser uma rede de segurança, crie um alerta no AWS Budgets.

Bedrock (embeddings na ingestão e consultas) e S3 cobram por uso e custam centavos neste volume.

## Testar no console

1. Abra o console do Amazon Bedrock em `us-east-1` e vá em **Knowledge Bases** → `sundog-rag`.
2. Clique em **Test knowledge base**, escolha um modelo para gerar respostas (ou desligue a geração para ver só os trechos recuperados) e faça uma pergunta sobre o livro.
3. A resposta deve citar trechos do documento do bucket. Se nada for encontrado, confira em **Data source** → `franks-book` se a última sincronização terminou com sucesso.

## Alternativa: S3 Vectors

Para custo quase zero, troque o OpenSearch Serverless pelo [Amazon S3 Vectors](https://docs.aws.amazon.com/AmazonS3/latest/userguide/s3-vectors.html), que cobra só por armazenamento, gravação e consultas, sem custo por hora. Com ele a KB poderia ficar sempre criada. A troca em `knowledge-base/` seria:

- substituir as políticas, a coleção, o `time_sleep` e o `opensearch_index` por um bucket vetorial e um índice (`aws_s3vectors_vector_bucket` e `aws_s3vectors_index`, com dimensão 1024 e métrica compatível);
- usar `storage_configuration { type = "S3_VECTORS" ... }` com `s3_vectors_configuration` na KB;
- trocar `aoss:APIAccessAll` na role da KB pelas permissões `s3vectors:*` necessárias no índice.

O S3 Vectors tem limites próprios (por exemplo, de metadados filtráveis e de recursos de busca); confira se atendem ao exercício do curso.
