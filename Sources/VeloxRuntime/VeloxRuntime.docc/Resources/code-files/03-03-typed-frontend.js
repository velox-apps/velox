// Fetch a single user
async function getUser(userId) {
    try {
        const response = await window.Velox.invoke('get_user', { id: userId });

        // response is fully typed - matches UserResponse
        console.log(`User: ${response.user.name}`);
        console.log(`Email: ${response.user.email}`);
        console.log(`Online: ${response.isOnline}`);

        // Access nested properties
        const createdDate = new Date(response.user.createdAt);
        console.log(`Member since: ${createdDate.toLocaleDateString()}`);

        return response.user;
    } catch (error) {
        console.error(`Failed to get user: ${error.message}`);
        throw error;
    }
}

// Fetch a list of users with pagination
async function listUsers(page = 1, limit = 10) {
    const response = await window.Velox.invoke('list_users', { page, limit });

    // response matches UsersListResponse
    console.log(`Showing ${response.users.length} of ${response.total} users`);

    // Iterate over the typed array
    response.users.forEach(user => {
        console.log(`- ${user.name} (${user.email})`);
    });

    return {
        users: response.users,
        hasMore: response.page * limit < response.total
    };
}
