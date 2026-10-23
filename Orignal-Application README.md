# E-Commerce Microservices Application

A full-stack MERN e-commerce application built with microservices architecture, featuring 4 separate Node.js backend services and a React frontend.

## 🏗️ Architecture Overview

This application demonstrates modern microservices architecture with the following components:

```
Frontend (React) → API Gateway → Microservices
                                    ├── User Service (3001)
                                    ├── Product Service (3002)
                                    ├── Cart Service (3003)
                                    └── Order Service (3004)
```

## 🔧 Technology Stack

### Backend
- **Runtime**: Node.js with Express.js
- **Database**: MongoDB with Mongoose ODM
- **Authentication**: JWT tokens
- **Architecture**: RESTful APIs with microservices

### Frontend
- **Framework**: React 18
- **Routing**: React Router
- **State Management**: React Query + Context API
- **HTTP Client**: Axios
- **Styling**: CSS3 with responsive design

## 📦 Microservices

### 1. User Service (Port 3001)
- User registration and authentication
- Profile management
- JWT token generation and validation
- User data persistence

**Endpoints:**
- `POST /api/auth/register` - User registration
- `POST /api/auth/login` - User authentication
- `GET /api/auth/me` - Get current user
- `GET /api/users/profile` - Get user profile
- `PUT /api/users/profile` - Update user profile

### 2. Product Service (Port 3002)
- Product catalog management
- Category management
- Product search and filtering
- Inventory tracking

**Endpoints:**
- `GET /api/products` - Get products with filtering/pagination
- `GET /api/products/:id` - Get single product
- `POST /api/products` - Create product (admin)
- `PUT /api/products/:id` - Update product (admin)
- `DELETE /api/products/:id` - Soft delete product (admin)
- `GET /api/categories` - Get all categories
- `POST /api/categories` - Create category (admin)

### 3. Cart Service (Port 3003)
- Shopping cart management
- Add/remove/update cart items
- Cart validation
- Integration with Product Service

**Endpoints:**
- `GET /api/cart/:userId` - Get user's cart
- `POST /api/cart/:userId/items` - Add item to cart
- `PUT /api/cart/:userId/items/:productId` - Update cart item
- `DELETE /api/cart/:userId/items/:productId` - Remove cart item
- `DELETE /api/cart/:userId` - Clear entire cart
- `POST /api/cart/:userId/validate` - Validate cart items

### 4. Order Service (Port 3004)
- Order creation and management
- Payment processing simulation
- Order status tracking
- Integration with Cart and Product Services

**Endpoints:**
- `GET /api/orders/user/:userId` - Get user's orders
- `GET /api/orders/:id` - Get single order
- `POST /api/orders` - Create new order
- `PUT /api/orders/:id/status` - Update order status
- `DELETE /api/orders/:id` - Cancel order
- `POST /api/payments/process` - Process payment
- `POST /api/payments/refund` - Process refund

## 🚀 Getting Started

### Prerequisites
- Node.js 16+ and npm
- MongoDB (local or cloud instance)

### Installation

1. **Clone the repository**
```bash
git clone <repository-url>
cd ecommerce-microservices
```

2. **Install dependencies for each service**
```bash

# Install User Service dependencies
cd backend/user-service && npm install

# Install Product Service dependencies
cd ../product-service && npm install

# Install Cart Service dependencies
cd ../cart-service && npm install

# Install Order Service dependencies
cd ../order-service && npm install

# Install Frontend dependencies
cd ../../frontend && npm install
```

3. **Set up environment variables**

Create `.env` files in each service directory:

**backend/user-service/.env:**
```env
PORT=3001
MONGODB_URI=mongodb://localhost:27017/ecommerce_users
JWT_SECRET=your-jwt-secret-key
```

**backend/product-service/.env:**
```env
PORT=3002
MONGODB_URI=mongodb://localhost:27017/ecommerce_products
```

**backend/cart-service/.env:**
```env
PORT=3003
MONGODB_URI=mongodb://localhost:27017/ecommerce_carts
PRODUCT_SERVICE_URL=http://localhost:3002
```

**backend/order-service/.env:**
```env
PORT=3004
MONGODB_URI=mongodb://localhost:27017/ecommerce_orders
CART_SERVICE_URL=http://localhost:3003
PRODUCT_SERVICE_URL=http://localhost:3002
USER_SERVICE_URL=http://localhost:3001
```

**frontend/.env:**
```env
REACT_APP_USER_SERVICE_URL=http://localhost:3001
REACT_APP_PRODUCT_SERVICE_URL=http://localhost:3002
REACT_APP_CART_SERVICE_URL=http://localhost:3003
REACT_APP_ORDER_SERVICE_URL=http://localhost:3004
```

### Running the Application


** Run services individually**

Terminal 1 - User Service:
```bash
cd backend/user-service && npm start
```

Terminal 2 - Product Service:
```bash
cd backend/product-service && npm start
```

Terminal 3 - Cart Service:
```bash
cd backend/cart-service && npm start
```

Terminal 4 - Order Service:
```bash
cd backend/order-service && npm start
```

Terminal 5 - Frontend:
```bash
cd frontend && npm start
```

The application will be available at:
- Frontend: http://localhost:3000
- User Service: http://localhost:3001
- Product Service: http://localhost:3002
- Cart Service: http://localhost:3003
- Order Service: http://localhost:3004

## 🎯 Features

### User Features
- **Authentication**: Register and login with JWT tokens
- **Product Browsing**: View products with search, filtering, and pagination
- **Shopping Cart**: Add, update, and remove items
- **Checkout Process**: Complete order placement with shipping and payment
- **Order Management**: View order history and track status
- **Profile Management**: Update personal information and addresses

### Admin Features (Future Enhancement)
- Product and category management
- Order status updates
- Inventory management
- User management

### Technical Features
- **Microservices Architecture**: Loosely coupled services
- **RESTful APIs**: Standard HTTP methods and status codes
- **Data Validation**: Input validation and error handling
- **Cross-Service Communication**: HTTP-based service interactions
- **Responsive Design**: Mobile-friendly user interface
- **Error Handling**: Comprehensive error management
- **Loading States**: User-friendly loading indicators

## 📁 Project Structure

```
ecommerce-microservices/
├── backend/
│   ├── user-service/
│   │   ├── models/
│   │   ├── routes/
│   │   ├── middleware/
│   │   ├── server.js
│   │   └── package.json
│   ├── product-service/
│   │   ├── models/
│   │   ├── routes/
│   │   ├── server.js
│   │   └── package.json
│   ├── cart-service/
│   │   ├── models/
│   │   ├── routes/
│   │   ├── server.js
│   │   └── package.json
│   └── order-service/
│       ├── models/
│       ├── routes/
│       ├── server.js
│       └── package.json
├── frontend/
│   ├── public/
│   ├── src/
│   │   ├── components/
│   │   ├── contexts/
│   │   ├── pages/
│   │   ├── services/
│   │   ├── App.js
│   │   └── index.js
│   └── package.json
├── package.json
└── README.md
```

## 🔧 API Testing

You can test the APIs using tools like Postman or curl:

```bash
# Health check for all services
curl http://localhost:3001/health
curl http://localhost:3002/health
curl http://localhost:3003/health
curl http://localhost:3004/health

# Register a new user
curl -X POST http://localhost:3001/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{"firstName":"John","lastName":"Doe","email":"john@example.com","password":"password123"}'

# Get products
curl http://localhost:3002/api/products

# Get categories
curl http://localhost:3002/api/categories
```

## 🚀 Deployment

### Production Considerations

1. **Environment Variables**: Use proper environment variable management
2. **Database**: Use MongoDB Atlas or other managed database services
3. **Process Management**: Use PM2 or similar for process management
4. **Load Balancing**: Implement load balancing for high availability
5. **Monitoring**: Add logging and monitoring solutions
6. **Security**: Implement rate limiting, CORS, and other security measures

### Docker Deployment (Future Enhancement)

Each service can be containerized with Docker:

```dockerfile
# Example Dockerfile for a service
FROM node:16-alpine
WORKDIR /app
COPY package*.json ./
RUN npm install --production
COPY . .
EXPOSE 3001
CMD ["npm", "start"]
```

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Commit your changes
4. Push to the branch
5. Create a Pull Request

## 📝 License

This project is licensed under the MIT License.

## 🆘 Support

For support and questions:
- Check the documentation
- Review API endpoints and expected payloads
- Ensure all services are running
- Verify database connections
- Check environment variables

## 🔮 Future Enhancements

- **API Gateway**: Centralized request routing and authentication
- **Docker Containerization**: Full containerization with docker-compose
- **Message Queues**: Async communication between services
- **Caching**: Redis caching for improved performance
- **Search Engine**: Elasticsearch for advanced product search
- **File Upload**: Image upload and management
- **Email Service**: Order confirmations and notifications
- **Admin Dashboard**: Administrative interface
- **Analytics**: Order and user analytics
- **Payment Integration**: Real payment gateway integration
