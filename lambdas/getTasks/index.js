const { DynamoDB } = require("aws-sdk");
const dynamo = new DynamoDB.DocumentClient();

exports.handler = async function () {
    try {
        const result = await dynamo.scan({
            TableName: process.env.TABLE_NAME
        }).promise();

        return {
            statusCode: 200,
            body: JSON.stringify(result.Items)
        };

    } catch (err) {
        console.error(err);
        return {
            statusCode: 500,
            body: JSON.stringify({ error: "Internal Server Error" })
        };
    }
}
