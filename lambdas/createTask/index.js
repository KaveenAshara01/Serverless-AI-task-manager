const axios = require("axios");
const { v4: uuidv4 } = require("uuid");


const { DynamoDBClient } = require("@aws-sdk/client-dynamodb");
const {
    DynamoDBDocumentClient,
    PutCommand,
} = require("@aws-sdk/lib-dynamodb");


const client = new DynamoDBClient({});
const dynamo = DynamoDBDocumentClient.from(client);

// HuggingFace Router – Roberta Zero-Shot Classification
const HF_MODEL_URL =
    "https://router.huggingface.co/hf-inference/models/facebook/bart-large-mnli";

const HUGGINGFACE_API_KEY = process.env.HF_API_KEY;

exports.handler = async (event) => {
    try {
        const body = JSON.parse(event.body || "{}");

        if (!body.description) {
            return {
                statusCode: 400,
                body: JSON.stringify({ error: "description is required" }),
            };
        }

        const description = body.description;

        const candidateLabels = [
            "work",
            "personal",
            "shopping",
            "study",
            "finance",
            "health",
            "travel",
        ];

        // HuggingFace Zero-Shot Classification
        const hfResponse = await axios.post(
            HF_MODEL_URL,
            {
                inputs: description,
                parameters: {
                    candidate_labels: candidateLabels,
                },
            },
            {
                headers: {
                    Authorization: `Bearer ${HUGGINGFACE_API_KEY}`,
                    "Content-Type": "application/json",
                },
                timeout: 20000,
            }
        );

        // HuggingFace router response structure
        const predictedCategory =
            hfResponse?.data?.labels?.[0] ||
            hfResponse?.data?.[0]?.labels?.[0] ||
            "uncategorized";

        const task = {
            id: uuidv4(),
            description,
            category: predictedCategory,
            createdAt: new Date().toISOString(),
        };

        await dynamo.send(
            new PutCommand({
                TableName: process.env.TABLE_NAME,
                Item: task,
            })
        );

        return {
            statusCode: 200,
            body: JSON.stringify(task),
        };

    } catch (err) {
        console.error("Error:", err);

        return {
            statusCode: 500,
            body: JSON.stringify({
                error: err.response?.data || err.message || "Internal Server Error",
            }),
        };
    }
};
