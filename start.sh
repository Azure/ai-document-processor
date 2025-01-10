#!/bin/bash
cd infra
az deployment group create --resource-group llm-doc-processing --template-file main.bicep --parameters main.parameters.json